import XCTest
import PreferansEngine

/// Lightweight UI smoke coverage for lobby wiring and single-deal transitions.
///
/// Deeper script replay lives in `MatchUITests` / `FullGameUITests`; this file
/// intentionally stays shallow and uses the same identifiers + robot helpers
/// as the rest of the UI suite so screen copy can evolve without breaking
/// tests that only care about behavior.
@MainActor
final class PreferansUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testLobbyRendersCoreControls() {
        let app = launchedApp()
        let robot = MatchUIRobot(app: app)

        robot.waitForElement(UIIdentifiers.lobbyTitle)
        robot.waitForElement(UIIdentifiers.lobbyQuickPlayVsBots)
        robot.waitForElement(UIIdentifiers.lobbyPlayerCountThree)
        robot.waitForElement(UIIdentifiers.lobbyPlayerCountFour)
        robot.waitForElement(UIIdentifiers.lobbyPlayerNameField(index: 0))
        robot.waitForElement(UIIdentifiers.lobbyBotToggle(index: 1))
        robot.waitForElement(UIIdentifiers.lobbyStartLocalTable)
    }

    func testStartLocalTableThenDeal() {
        let app = launchedApp()
        let robot = MatchUIRobot(app: app)

        robot.startLocalTable()
        robot.waitForPhase("Waiting for deal")
        robot.startNextDeal()

        robot.waitForPhase("Bidding")
        robot.waitForElement(UIIdentifiers.Panel.currentTrick.rawValue)
        robot.waitForElement(UIIdentifiers.Panel.bidding.rawValue)
    }

    func testFourPlayerRosterAddsSeat() {
        let app = launchedApp()
        let robot = MatchUIRobot(app: app)

        robot.selectPlayerCount(4)

        robot.waitForElement(UIIdentifiers.lobbyPlayerNameField(index: 3))
        robot.waitForElement(UIIdentifiers.lobbyBotToggle(index: 3))
    }

    func testBiddingExposesPassAndMisereOptions() {
        let app = launchedApp(extraArguments: [UITestFlags.viewerFollowsActor])
        let robot = MatchUIRobot(app: app)

        robot.startLocalTable()
        robot.startNextDeal()
        robot.waitForPhase("Bidding")

        robot.waitForElement(UIIdentifiers.Panel.bidding.rawValue)
        robot.waitForElement(UIIdentifiers.bidButton(.pass))
        robot.waitForElement(UIIdentifiers.bidButton(.bid(.misere)))
    }

    func testAllPassDrivesEngineIntoPlayingPhase() {
        let app = launchedApp(extraArguments: manualThreePlayerHarness())
        let robot = MatchUIRobot(app: app)

        robot.startLocalTable()
        robot.startNextDeal()
        robot.waitForPhase("Bidding")

        for _ in 0..<3 {
            robot.bid(.pass)
        }

        robot.waitForPhase("Playing")
    }

    func testDeterministicScenarioPinsFirstBidder() {
        let app = launchedApp(extraArguments: manualThreePlayerHarness() + [
            UITestFlags.dealScenario, "sortedDeck"
        ])
        let robot = MatchUIRobot(app: app)

        robot.startLocalTable()
        robot.startNextDeal()

        robot.waitForPhase("Bidding")
        XCTAssertEqual(robot.currentViewer(), "north")
        XCTAssertEqual(robot.phaseMessage(), "Auction: north to call.")
    }

    func testNorthSpadesSixScenarioDrivesEngineToDiscardWindow() {
        let app = launchedApp(extraArguments: manualThreePlayerHarness() + [
            UITestFlags.dealScenario, "northBidsSpadesSix"
        ])
        let robot = MatchUIRobot(app: app)

        robot.startLocalTable()
        robot.startNextDeal()
        robot.waitForPhase("Bidding")

        robot.bid(.bid(.game(GameContract(6, .suit(.spades)))))
        XCTAssertEqual(robot.currentViewer(), "east")
        robot.bid(.pass)
        XCTAssertEqual(robot.currentViewer(), "south")
        robot.bid(.pass)

        robot.waitForPhase("Talon exchange")
        robot.waitForElement(UIIdentifiers.Panel.discard.rawValue)
        XCTAssertEqual(robot.currentViewer(), "north")
    }

    func testGameScreenShowsCoreSectionsAfterDeal() {
        let app = launchedApp()
        let robot = MatchUIRobot(app: app)

        robot.startLocalTable()
        robot.startNextDeal()
        robot.waitForPhase("Bidding")

        robot.waitForElement(UIIdentifiers.phaseMessage)
        robot.waitForElement(UIIdentifiers.viewerLabel)
        robot.waitForElement(UIIdentifiers.Panel.currentTrick.rawValue)
        robot.waitForElement(UIIdentifiers.Panel.bidding.rawValue)
    }

    private func launchedApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += extraArguments
        app.disableUITestAnimations()
        app.launch()
        return app
    }

    private func manualThreePlayerHarness() -> [String] {
        [
            UITestFlags.viewerFollowsActor,
            UITestFlags.players, "north,east,south",
            UITestFlags.firstDealer, "south"
        ]
    }
}
