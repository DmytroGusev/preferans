import XCTest
@testable import PreferansApp

@MainActor
final class RoomDurabilityRetryRunnerTests: AppTestCase {
    func testRunnerCapsBackoffAndPublishesOnlyAfterPersistence() async {
        let delays = DurabilityDelayRecorder()
        let runner = RoomDurabilityRetryRunner<Int>(
            initialDelay: .milliseconds(1),
            maximumDelay: .milliseconds(4),
            sleep: { duration in await delays.record(duration) }
        )
        var attempts = 0
        var failures = 0
        var events: [String] = []

        XCTAssertTrue(runner.start(
            7,
            isCurrent: { true },
            persist: { update in
                attempts += 1
                events.append("persist:\(update):\(attempts)")
                if attempts <= 3 {
                    throw DurabilityRunnerTestError.unavailable
                }
            },
            publish: { update in events.append("publish:\(update)") },
            onRetryFailure: { _, _ in failures += 1 },
            onSuccess: { events.append("success") }
        ))
        await waitUntil { events.last == "success" && !runner.hasActiveWork }
        let recordedDelays = await delays.values

        XCTAssertEqual(attempts, 4)
        XCTAssertEqual(failures, 3)
        XCTAssertEqual(
            recordedDelays,
            [.milliseconds(1), .milliseconds(2), .milliseconds(4), .milliseconds(4)]
        )
        XCTAssertEqual(Array(events.suffix(3)), ["persist:7:4", "publish:7", "success"])
        XCTAssertTrue(runner.acceptsAction)
        XCTAssertFalse(runner.isRetrying)
    }

    func testRunnerRejectsConcurrentUpdateWhileFirstIsPending() async {
        let sleepGate = DurabilitySleepGate()
        let runner = RoomDurabilityRetryRunner<Int>(
            initialDelay: .milliseconds(1),
            sleep: { duration in await sleepGate.suspend(duration) }
        )

        XCTAssertTrue(runner.start(
            1,
            isCurrent: { true },
            persist: { _ in },
            publish: { _ in },
            onRetryFailure: { _, _ in },
            onSuccess: {}
        ))
        await waitUntil { await sleepGate.isSuspended }

        XCTAssertFalse(runner.acceptsAction)
        XCTAssertFalse(runner.start(
            2,
            isCurrent: { true },
            persist: { _ in },
            publish: { _ in },
            onRetryFailure: { _, _ in },
            onSuccess: {}
        ))

        await sleepGate.resume()
        await waitUntil { !runner.hasActiveWork }
        XCTAssertTrue(runner.acceptsAction)
    }

    func testCancelledNonCooperativeWriteCannotPublishOrClearNewerUpdate() async {
        let persistenceGate = DurabilityPersistenceGate()
        let runner = RoomDurabilityRetryRunner<Int>(
            initialDelay: .nanoseconds(1),
            sleep: { _ in }
        )
        var published: [Int] = []
        var succeeded: [Int] = []

        XCTAssertTrue(runner.start(
            1,
            isCurrent: { true },
            persist: { update in
                if update == 1 {
                    await persistenceGate.suspend()
                }
            },
            publish: { published.append($0) },
            onRetryFailure: { _, _ in },
            onSuccess: { succeeded.append(1) }
        ))
        await waitUntil { await persistenceGate.isSuspended }

        runner.cancel()
        XCTAssertFalse(runner.isRetrying)
        XCTAssertTrue(runner.hasActiveWork)
        XCTAssertTrue(runner.start(
            2,
            isCurrent: { true },
            persist: { _ in },
            publish: { published.append($0) },
            onRetryFailure: { _, _ in },
            onSuccess: { succeeded.append(2) }
        ))
        await waitUntil { succeeded == [2] }

        await persistenceGate.resume()
        await waitUntil { !runner.hasActiveWork }

        XCTAssertEqual(published, [2])
        XCTAssertEqual(succeeded, [2])
        XCTAssertTrue(runner.acceptsAction)
    }

    func testHostActionQueueRunsMutationsInSubmissionOrder() async {
        let gate = DurabilityPersistenceGate()
        let queue = RoomHostActionQueue()
        var events: [String] = []

        queue.enqueue {
            events.append("first:start")
            await gate.suspend()
            events.append("first:end")
        }
        await waitUntil { await gate.isSuspended }

        queue.enqueue {
            events.append("second")
        }
        await Task.yield()
        XCTAssertEqual(events, ["first:start"])

        await gate.resume()
        await waitUntil { events == ["first:start", "first:end", "second"] }
    }

    func testHostActionQueueCancellationDropsQueuedMutations() async {
        let gate = DurabilityPersistenceGate()
        let queue = RoomHostActionQueue()
        var events: [String] = []

        queue.enqueue {
            events.append("first:start")
            await gate.suspend()
            events.append("first:end")
        }
        await waitUntil { await gate.isSuspended }
        queue.enqueue { events.append("second") }
        queue.cancel()
        await gate.resume()
        await Task.yield()

        XCTAssertEqual(events, ["first:start", "first:end"],
                       "Cancellation must drop actions queued behind a detached host epoch.")
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () async -> Bool,
        timeout: Duration = .milliseconds(750),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            await Task.yield()
        }
        let didSucceed = await condition()
        XCTAssertTrue(didSucceed, file: file, line: line)
    }
}

private actor DurabilityDelayRecorder {
    private(set) var values: [Duration] = []

    func record(_ duration: Duration) {
        values.append(duration)
    }
}

private actor DurabilitySleepGate {
    private var continuation: CheckedContinuation<Void, Never>?

    var isSuspended: Bool { continuation != nil }

    func suspend(_ duration: Duration) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}

private actor DurabilityPersistenceGate {
    private var continuation: CheckedContinuation<Void, Never>?

    var isSuspended: Bool { continuation != nil }

    func suspend() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}

private enum DurabilityRunnerTestError: Error {
    case unavailable
}
