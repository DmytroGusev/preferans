import XCTest
@testable import PreferansApp
@testable import PreferansEngine

@MainActor
final class RoomHostRecoveryRunnerTests: AppTestCase {
    func testRunnerRetriesWithBoundedBackoffThenPromotesOnce() async {
        let transport = RecoveryTransportStub(localPlayerID: "east", electedHostID: "east")
        transport.recoveryFailuresRemaining = 3
        let delays = RecoveryDelayRecorder()
        let runner = RoomHostRecoveryRunner(
            initialDelay: .milliseconds(1),
            maximumDelay: .milliseconds(4),
            sleep: { duration in await delays.record(duration) }
        )
        var retryCount = 0
        var promotionCount = 0
        var succeeded = false

        runner.start(
            transport: transport,
            expectedHost: "east",
            isCurrent: { true },
            promote: { _ in promotionCount += 1 },
            onRetry: { _ in retryCount += 1 },
            onSuccess: { succeeded = true }
        )
        await waitUntil { succeeded && !runner.hasActiveWork }
        let recordedDelays = await delays.values

        XCTAssertEqual(transport.recoveryAttemptCount, 4)
        XCTAssertEqual(retryCount, 3)
        XCTAssertEqual(promotionCount, 1)
        XCTAssertEqual(
            recordedDelays,
            [.milliseconds(1), .milliseconds(2), .milliseconds(4)]
        )
        XCTAssertFalse(runner.isRecovering)
    }

    func testCancelInvalidatesANonCooperativeRecoveryAwait() async {
        let transport = RecoveryTransportStub(localPlayerID: "east", electedHostID: "east")
        transport.suspendsRecoveryContext = true
        let runner = RoomHostRecoveryRunner(
            initialDelay: .milliseconds(1),
            maximumDelay: .milliseconds(2)
        )
        var isCurrent = true
        var retryCount = 0
        var promotionCount = 0
        var succeeded = false

        runner.start(
            transport: transport,
            expectedHost: "east",
            isCurrent: { isCurrent },
            promote: { _ in promotionCount += 1 },
            onRetry: { _ in retryCount += 1 },
            onSuccess: { succeeded = true }
        )
        await waitUntil { transport.recoveryAttemptCount == 1 }

        isCurrent = false
        runner.cancel()
        XCTAssertFalse(runner.isRecovering)
        XCTAssertTrue(runner.hasActiveWork)
        transport.resumeRecoveryContext()
        await waitUntil { !runner.hasActiveWork }

        XCTAssertEqual(retryCount, 0)
        XCTAssertEqual(promotionCount, 0)
        XCTAssertFalse(succeeded)
        XCTAssertEqual(transport.hostChoiceAttemptCount, 0)
    }

    func testChangedServerElectionStopsPromotionAfterRecoveryContextReturns() async {
        let transport = RecoveryTransportStub(localPlayerID: "east", electedHostID: "east")
        transport.suspendsHostChoice = true
        let runner = RoomHostRecoveryRunner(
            initialDelay: .milliseconds(1),
            maximumDelay: .milliseconds(2)
        )
        var retryCount = 0
        var promotionCount = 0
        var succeeded = false

        runner.start(
            transport: transport,
            expectedHost: "east",
            isCurrent: { true },
            promote: { _ in promotionCount += 1 },
            onRetry: { _ in retryCount += 1 },
            onSuccess: { succeeded = true }
        )
        await waitUntil { transport.hostChoiceAttemptCount == 1 }

        transport.electedHostID = "south"
        transport.resumeHostChoice()
        await waitUntil { !runner.hasActiveWork }

        XCTAssertEqual(transport.recoveryAttemptCount, 1)
        XCTAssertEqual(retryCount, 0)
        XCTAssertEqual(promotionCount, 0)
        XCTAssertFalse(succeeded)
        XCTAssertFalse(runner.isRecovering)
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        timeout: Duration = .milliseconds(750),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            await Task.yield()
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }
}

private actor RecoveryDelayRecorder {
    private(set) var values: [Duration] = []

    func record(_ duration: Duration) {
        values.append(duration)
    }
}

@MainActor
private final class RecoveryTransportStub: RoomRealtimeTransport {
    let localPeer: OnlinePeer
    let participants: [OnlinePeer]
    var electedHostID: PlayerID
    var recoveryFailuresRemaining = 0
    var suspendsRecoveryContext = false
    var suspendsHostChoice = false
    private(set) var recoveryAttemptCount = 0
    private(set) var hostChoiceAttemptCount = 0

    private var recoveryContinuation: CheckedContinuation<Void, Never>?
    private var hostChoiceContinuation: CheckedContinuation<Void, Never>?

    init(localPlayerID: PlayerID, electedHostID: PlayerID) {
        let players: [PlayerID] = ["north", "east", "south"]
        let peers = players.map { player in
            OnlinePeer(
                playerID: player,
                accountID: "dev:\(player.rawValue)",
                provider: .dev,
                displayName: player.rawValue.capitalized
            )
        }
        self.participants = peers
        self.localPeer = peers.first { $0.playerID == localPlayerID }!
        self.electedHostID = electedHostID
    }

    func chooseHost() async -> OnlinePeer? {
        hostChoiceAttemptCount += 1
        if suspendsHostChoice {
            await withCheckedContinuation { continuation in
                hostChoiceContinuation = continuation
            }
        }
        return participants.first { $0.playerID == electedHostID }
    }

    func messages() -> AsyncStream<ReceivedRoomMessage> {
        AsyncStream { $0.finish() }
    }

    func send(_ message: GameWireMessage, to peers: [OnlinePeer], reliably: Bool) async throws {}

    func sendToAll(_ message: GameWireMessage, reliably: Bool) async throws {}

    func hostRecoveryContext() async throws -> OnlineResumeContext? {
        recoveryAttemptCount += 1
        if recoveryFailuresRemaining > 0 {
            recoveryFailuresRemaining -= 1
            throw RecoveryRunnerTestError.unavailable
        }
        if suspendsRecoveryContext {
            await withCheckedContinuation { continuation in
                recoveryContinuation = continuation
            }
        }
        return nil
    }

    func disconnect() {
        resumeRecoveryContext()
        resumeHostChoice()
    }

    func resumeRecoveryContext() {
        suspendsRecoveryContext = false
        let continuation = recoveryContinuation
        recoveryContinuation = nil
        continuation?.resume()
    }

    func resumeHostChoice() {
        suspendsHostChoice = false
        let continuation = hostChoiceContinuation
        hostChoiceContinuation = nil
        continuation?.resume()
    }
}

private enum RecoveryRunnerTestError: Error {
    case unavailable
}
