import Dependencies
import XCTest

/// Base class for tests that exercise app-layer code (`GameViewModel`,
/// `LobbyViewModel`, `InMemoryOnlineGameSession`) which now read
/// `\.continuousClock` and `\.uuid` via `swift-dependencies`. The default
/// `testValue` for `\.continuousClock` is `unimplemented`, so unmodified
/// tests would fail the moment a bot task or idle-hint timer schedules a
/// sleep. Wrapping every test in this class with `ImmediateClock` and a
/// deterministic UUID generator preserves the prior behavior (real
/// `Task.sleep` was effectively a no-op for tests that never awaited it).
///
/// Tests that want to assert time-based behavior should override the clock
/// inside their body with `withDependencies { $0.continuousClock = TestClock() }`.
class AppTestCase: XCTestCase {
    override func invokeTest() {
        withDependencies {
            $0.continuousClock = ImmediateClock()
            $0.uuid = .incrementing
        } operation: {
            super.invokeTest()
        }
    }
}
