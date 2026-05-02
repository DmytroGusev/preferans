import XCTest
import PreferansEngine

/// End-to-end UI tests that drive each canonical match script
/// through the SwiftUI surface via `MatchUIDriver` + `MatchUIRobot`.
///
/// Every test:
/// 1. Launches the app with the matching `-uiTestMatchScript` flag so the
///    lobby resolves players, firstDealer, rules, MatchSettings, and a
///    pre-built scripted deal source from `MatchScriptFixtures`.
/// 2. Taps "Start Local Table" via the robot.
/// 3. Hands the script and robot to `MatchUIDriver(...).run()`, which
///    replays every action through the UI while mirroring an internal
///    engine and cross-checking the score.
/// 4. The driver itself asserts the game-over panel matches the engine's
///    summary — the per-test body just checks the deal count.
@MainActor
final class FullGameUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testGame1_ClassicSochi() throws {
        try runScript("game1", expected: MatchScriptFixtures.game1ClassicSochi)
    }

    func testGame2_LongSochi() throws {
        try runScript("game2", expected: MatchScriptFixtures.game2LongSochi)
    }

    func testGame3_RostovDedicatedTotus() throws {
        try runScript("game3", expected: MatchScriptFixtures.game3RostovDedicatedTotus)
    }

    private func runScript(_ harnessName: String, expected script: MatchScript) throws {
        let app = XCUIApplication()
        app.configureForMatchScript(harnessName)
        app.launch()

        let robot = MatchUIRobot(app: app)
        robot.startLocalTable()

        try MatchUIDriver(script: script, robot: robot).run()

        XCTAssertEqual(robot.gameOverDealsPlayed(), script.deals.count,
                       "Game-over panel must report exactly the scripted deal count.")
    }
}
