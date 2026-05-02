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
    /// the engine transitions through `Bidding → Talon exchange` while the
    /// robot's readings stay coherent with the engine's state.
    func testRobotDrivesGame1FirstAuctionToTalonExchange() {
        let app = XCUIApplication()
        app.configureForMatchScript("game1")
        app.launch()

        let robot = MatchUIRobot(app: app)

        // Lobby — start the local table with the script's pre-resolved roster.
        robot.startLocalTable()

        // Match begins in waitingForDeal — user (or test) clicks Start Deal
        // to consume the first scripted deck.
        robot.waitForPhase("Waiting for deal")
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

        // West passes — auction ends, talon exchange opens with east declaring.
        robot.bid(.pass)
        robot.waitForPhase("Talon exchange")
        XCTAssertEqual(robot.currentViewer(), "east",
                       "viewer should follow the declarer into the discard window.")

        // No score has accrued yet — the deal is mid-flight.
        XCTAssertEqual(robot.scoreSnapshot(for: ["east"])["east"]?.pool, 0)
        XCTAssertNil(robot.errorBanner(), "Engine should not have surfaced any errors during the auction.")
    }
}
