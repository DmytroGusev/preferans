import Foundation
import PreferansEngine

/// Single-flight retry orchestration for a server-elected replacement host.
/// The runner owns retry timing, validates the server election around every
/// await, and invalidates non-cooperative work by generation. The coordinator
/// supplies the actual promotion transaction so authority state stays local.
@MainActor
final class RoomHostRecoveryRunner {
    typealias Sleep = @Sendable (Duration) async -> Void

    private let retryBackoff: RoomRetryBackoff
    private let sleep: Sleep
    private var pendingTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var activeTickets: Set<UInt64> = []

    init(
        initialDelay: Duration,
        maximumDelay: Duration,
        sleep: @escaping Sleep = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.retryBackoff = RoomRetryBackoff(
            initialDelay: initialDelay,
            maximumDelay: maximumDelay
        )
        self.sleep = sleep
    }

    deinit {
        pendingTask?.cancel()
    }

    var isRecovering: Bool { pendingTask != nil }
    /// Includes invalidated work whose transport await has not returned yet.
    var hasActiveWork: Bool { !activeTickets.isEmpty }

    func cancel() {
        generation &+= 1
        pendingTask?.cancel()
        pendingTask = nil
    }

    func start(
        transport: any RoomRealtimeTransport,
        expectedHost: PlayerID,
        isCurrent: @escaping @MainActor () -> Bool,
        promote: @escaping @MainActor (OnlineResumeContext?) async throws -> Void,
        onRetry: @escaping @MainActor (Error) -> Void,
        onSuccess: @escaping @MainActor () -> Void
    ) {
        cancel()
        let ticket = generation
        let sleep = self.sleep
        let baseBackoff = retryBackoff
        activeTickets.insert(ticket)

        pendingTask = Task { @MainActor [weak self] in
            defer {
                if let self {
                    self.activeTickets.remove(ticket)
                    if self.generation == ticket {
                        self.pendingTask = nil
                    }
                }
            }

            var backoff = baseBackoff
            while let self,
                  self.generation == ticket,
                  isCurrent(),
                  !Task.isCancelled {
                do {
                    let resume = try await transport.hostRecoveryContext()
                    guard self.generation == ticket,
                          isCurrent(),
                          !Task.isCancelled,
                          let elected = await transport.chooseHost(),
                          elected.playerID == expectedHost,
                          elected.playerID == transport.localPeer.playerID,
                          self.generation == ticket,
                          isCurrent(),
                          !Task.isCancelled else { return }

                    try await promote(resume)
                    guard self.generation == ticket,
                          isCurrent(),
                          !Task.isCancelled else { return }
                    onSuccess()
                    return
                } catch is CancellationError {
                    return
                } catch {
                    guard self.generation == ticket,
                          isCurrent(),
                          !Task.isCancelled else { return }
                    onRetry(error)
                    await sleep(backoff.currentDelay)
                    guard self.generation == ticket,
                          isCurrent(),
                          !Task.isCancelled else { return }
                    backoff.recordFailure()
                }
            }
        }
    }
}
