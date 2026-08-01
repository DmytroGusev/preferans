import XCTest
import PreferansEngine

/// Step-5 smoke test: drives one auction through the `MatchUIRobot` against
/// the Game-1 canonical fixture and asserts the robot's reads match the
/// engine's expected behaviour. Verifies plumbing only — full deal play-out
/// and end-to-end multi-deal driving belong to step 6 (`MatchUIDriver`).
@MainActor
final class MatchUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Launches with Game 1 (`firstDealer = north`, 4 players, classic Sochi,
    /// `asTenTrickGame(requireWhist: false)`, `poolTarget = 20`). Drives the
    /// first deal's auction (east opens 6♠, south and west pass) and asserts
    /// the engine transitions through `Bidding → Prikup` while the
    /// robot's readings stay coherent with the engine's state.
    func testRobotDrivesGame1FirstAuctionToTalonExchange() {
        let app = XCUIApplication()
        app.configureForMatchScript("game1")
        app.launch()

        let robot = MatchUIRobot(app: app)

        // Lobby — start the local table with the script's pre-resolved roster.
        robot.startLocalTable()

        // Match begins in waitingForDeal — user (or test) clicks Deal
        // to consume the first scripted deck.
        robot.waitForPhase("Ready")
        robot.startNextDeal()

        // Bidding opens with east as the active rotation's first bidder.
        robot.waitForPhase("Bidding")
        XCTAssertEqual(robot.currentViewer(), "east",
                       "viewerFollowsActor should pin the viewer to the first bidder.")

        // Score sheet is empty before any deal scores.
        let initialScores = robot.scoreSnapshot(for: MatchScriptFixtures.players)
        for player in MatchScriptFixtures.players {
            XCTAssertEqual(initialScores[player]?.pool, 0, "Pool for \(player) must start at 0.")
            XCTAssertEqual(initialScores[player]?.mountain, 0, "Mountain for \(player) must start at 0.")
        }

        // East opens 6♠.
        let sixSpades = BidCall.bid(.game(GameContract(6, .suit(.spades))))
        robot.bid(sixSpades)
        robot.waitForPhase("Bidding") // still bidding — south's turn now

        XCTAssertEqual(robot.currentViewer(), "south",
                       "viewer should rotate to south after east's bid.")

        // South passes — viewer rotates to west.
        robot.bid(.pass)
        robot.waitForPhase("Bidding")
        XCTAssertEqual(robot.currentViewer(), "west")

        // West passes — auction ends, prikup exchange opens with east declaring.
        robot.bid(.pass)
        robot.waitForPhase("Prikup")
        XCTAssertEqual(robot.currentViewer(), "east",
                       "viewer should follow the declarer into the discard window.")

        // No score has accrued yet — the deal is mid-flight.
        XCTAssertEqual(robot.scoreSnapshot(for: ["east"])["east"]?.pool, 0)
        XCTAssertNil(robot.errorBanner(), "Engine should not have surfaced any errors during the auction.")
    }

    /// The optional ten-trick whist convention enters the ordinary defense
    /// decision flow. It must not turn the deal into a forced-whist variant:
    /// both defenders may independently pass, and half-whist is unavailable
    /// above level seven.
    func testTenTrickConventionOffersBothDefendersPassOrWhist() {
        let app = XCUIApplication()
        app.launchArguments += [
            UITestFlags.viewerFollowsActor,
            UITestFlags.players, "north,east,south",
            UITestFlags.firstDealer, "south",
            UITestFlags.dealScenario, "sortedDeck",
            UITestFlags.totusPolicy, "asTenTrickGame:true",
        ]
        app.disableUITestAnimations()
        app.launch()

        let robot = MatchUIRobot(app: app)
        let contract = GameContract(10, .suit(.spades))

        robot.startLocalTable()
        robot.startNextDeal()
        robot.waitForPhase("Bidding")

        robot.bid(.bid(.game(contract)))
        robot.bid(.pass)
        robot.bid(.pass)

        robot.waitForPhase("Prikup")
        robot.takeTalon()
        robot.discard([
            Card(.spades, .king),
            Card(.spades, .ace),
        ])
        robot.waitForPhase("Contract")
        robot.declareContract(contract)

        robot.waitForPhase("Whist")
        XCTAssertEqual(robot.currentViewer(), "east")
        XCTAssertTrue(app.buttons[UIIdentifiers.whistButton(.pass)].exists)
        XCTAssertTrue(app.buttons[UIIdentifiers.whistButton(.whist)].exists)
        XCTAssertFalse(app.buttons[UIIdentifiers.whistButton(.halfWhist)].exists)
        robot.whist(.pass)

        robot.waitForPhase("Whist")
        XCTAssertEqual(robot.currentViewer(), "south")
        XCTAssertTrue(app.buttons[UIIdentifiers.whistButton(.pass)].exists)
        XCTAssertTrue(app.buttons[UIIdentifiers.whistButton(.whist)].exists)
        XCTAssertFalse(app.buttons[UIIdentifiers.whistButton(.halfWhist)].exists)
        robot.whist(.pass)

        robot.waitForPhase("Deal complete")
        XCTAssertEqual(robot.scoreSnapshot(for: ["north"])["north"]?.pool, 10)
        XCTAssertNil(robot.errorBanner())
    }
}
