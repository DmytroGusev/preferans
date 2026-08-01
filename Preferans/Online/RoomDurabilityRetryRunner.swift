import Foundation

/// Single-flight retry lifecycle for a host update that must become durable
/// before it is visible. The runner owns timing and ticket invalidation; its
/// caller retains the actual persistence and publication transactions.
@MainActor
final class RoomDurabilityRetryRunner<Update> {
    typealias Sleep = @Sendable (Duration) async -> Void

    private var barrier: RoomDurabilityBarrier<Update>
    private let sleep: Sleep
    private var pendingTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var activeWorkCount = 0

    init(
        initialDelay: Duration,
        maximumDelay: Duration = .seconds(8),
        sleep: @escaping Sleep = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.barrier = RoomDurabilityBarrier(
            initialRetryDelay: initialDelay,
            maximumRetryDelay: maximumDelay
        )
        self.sleep = sleep
    }

    deinit {
        pendingTask?.cancel()
    }

    var acceptsAction: Bool {
        barrier.acceptsAction && pendingTask == nil
    }

    var isRetrying: Bool { pendingTask != nil }

    /// Includes invalidated work whose persistence await has not returned yet.
    var hasActiveWork: Bool { activeWorkCount > 0 }

    func cancel() {
        generation &+= 1
        pendingTask?.cancel()
        pendingTask = nil
        barrier.reset()
    }

    @discardableResult
    func start(
        _ update: Update,
        isCurrent: @escaping @MainActor () -> Bool,
        persist: @escaping @MainActor (Update) async throws -> Void,
        publish: @escaping @MainActor (Update) async -> Void,
        onRetryFailure: @escaping @MainActor (Update, Error) -> Void,
        onSuccess: @escaping @MainActor () -> Void
    ) -> Bool {
        guard pendingTask == nil, let ticket = barrier.stage(update) else {
            return false
        }

        generation &+= 1
        let runGeneration = generation
        let sleep = self.sleep
        activeWorkCount += 1

        pendingTask = Task { @MainActor [weak self] in
            defer {
                if let self {
                    self.activeWorkCount -= 1
                    if self.generation == runGeneration {
                        self.pendingTask = nil
                    }
                }
            }

            while let self,
                  self.generation == runGeneration,
                  isCurrent(),
                  !Task.isCancelled {
                guard let delay = self.barrier.delay(for: ticket) else { return }
                await sleep(delay)
                guard self.generation == runGeneration,
                      isCurrent(),
                      !Task.isCancelled,
                      let pending = self.barrier.update(for: ticket) else { return }

                do {
                    try await persist(pending)
                    guard self.generation == runGeneration,
                          isCurrent(),
                          !Task.isCancelled,
                          self.barrier.update(for: ticket) != nil else { return }

                    await publish(pending)
                    guard self.generation == runGeneration,
                          isCurrent(),
                          !Task.isCancelled,
                          self.barrier.complete(ticket) != nil else { return }
                    onSuccess()
                    return
                } catch is CancellationError {
                    return
                } catch {
                    guard self.generation == runGeneration,
                          isCurrent(),
                          !Task.isCancelled,
                          self.barrier.update(for: ticket) != nil else { return }
                    onRetryFailure(pending, error)
                    guard self.barrier.recordFailure(for: ticket) else { return }
                }
            }
        }
        return true
    }
}
