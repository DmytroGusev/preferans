import XCTest
import PreferansEngine

/// Exercises the online waiting room end-to-end without a worker or a second
/// device, using the DEBUG in-memory all-bot room: switch to the online flow,
/// spin up the room, confirm we land on the WAITING ROOM (not a bare felt),
/// then host-start into the live table.
@MainActor
final class OnlineWaitingRoomUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testInMemoryRoomLandsOnWaitingRoomThenStarts() {
        let app = XCUIApplication()
        app.disableUITestAnimations()
        // Spin up the all-bot in-memory room on launch — deterministic, no
        // worker and no second device.
        app.launchArguments += [UITestFlags.autoCreateInMemoryRoom]
        app.launch()
        let robot = MatchUIRobot(app: app)

        // We should land on the waiting room — not straight onto the felt.
        robot.waitForElement(UIIdentifiers.screenWaitingRoom)
        robot.waitForElement(UIIdentifiers.onlineRoomCode)

        // Roster occupancy renders: the local player is "you" and the others
        // are bots. Seats sort by canonical id (east, north, south), so the
        // local north seat lands at index 1.
        let youSeat = app.descendants(matching: .any)
            .matching(identifier: UIIdentifiers.waitingRoomSeat(index: 1)).element
        XCTAssertTrue(youSeat.waitForExistence(timeout: 5), "Waiting-room seats never appeared.")
        XCTAssertEqual(youSeat.value as? String, "you", "The local player's seat should read as 'you'.")
        let botSeat = app.descendants(matching: .any)
            .matching(identifier: UIIdentifiers.waitingRoomSeat(index: 0)).element
        XCTAssertEqual(botSeat.value as? String, "bot", "Empty seats should be filled by bots.")

        // The all-bot room is fully seated, so the host can start immediately.
        let start = app.buttons[UIIdentifiers.onlineStartGame]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "Start button never appeared.")
        XCTAssertTrue(start.isEnabled, "Start should be enabled once every seat is filled.")
        start.tap()

        // The table goes live.
        robot.waitForElement(UIIdentifiers.screenGame)

        // Once the human yields the auction, the production-style host bot
        // should publish the same public-safe rationale available in local play.
        var sawInsight = false
        for _ in 0..<8 {
            if app.descendants(matching: .any)[UIIdentifiers.botInsightBanner]
                .waitForExistence(timeout: 0.6) {
                sawInsight = true
                break
            }
            if robot.tapIfPresent(UIIdentifiers.bidButton(.pass)) {
                continue
            }
        }
        XCTAssertTrue(sawInsight, "Online bot rationale never reached the live table.")
    }

    func testHostFillsOpenSeatsTransactionallyThenStarts() {
        let app = XCUIApplication()
        app.disableUITestAnimations()
        app.launchArguments += [UITestFlags.autoCreateInMemoryInviteRoom]
        app.launch()
        let robot = MatchUIRobot(app: app)

        robot.waitForElement(UIIdentifiers.screenWaitingRoom)
        let start = app.buttons[UIIdentifiers.onlineStartGame]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertFalse(start.isEnabled, "Open seats must keep Start disabled.")

        let openSeat = app.descendants(matching: .any)
            .matching(identifier: UIIdentifiers.waitingRoomSeat(index: 0)).element
        XCTAssertTrue(openSeat.waitForExistence(timeout: 2))
        XCTAssertEqual(openSeat.value as? String, "open")

        let fill = app.buttons[UIIdentifiers.onlineFillWithBots]
        XCTAssertTrue(fill.waitForExistence(timeout: 2))
        for _ in 0..<4 where !fill.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(fill.isHittable)
        fill.tap()

        robot.waitForElement(UIIdentifiers.screenGame)
    }

    func testOnlineCompletedTrickShowsTimedResultHold() {
        let app = XCUIApplication()
        app.disableUITestAnimations()
        app.launchArguments += [
            UITestFlags.autoCreateInMemoryRoom,
            UITestFlags.onlineFlowLogging,
            UITestFlags.dealScenario, "northBidsSpadesSix",
        ]
        app.launch()
        let robot = MatchUIRobot(app: app)

        robot.waitForElement(UIIdentifiers.screenWaitingRoom)
        let start = app.buttons[UIIdentifiers.onlineStartGame]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        robot.waitForElement(UIIdentifiers.screenGame)

        let hold = app.descendants(matching: .any)
            .matching(identifier: UIIdentifiers.trickResultHold)
            .firstMatch
        var sawHold = false
        for iteration in 0..<5 {
            let flow = app.descendants(matching: .any)[UIIdentifiers.onlineFlowState]
            print("[online-hold] iteration=\(iteration) flow=\(flow.value ?? "missing")")
            if hold.exists {
                sawHold = true
                break
            }
            if robot.tapIfPresent(UIIdentifiers.bidButton(.pass)) { continue }
            if robot.tapIfPresent(UIIdentifiers.whistButton(.pass)) { continue }
            if robot.tapIfPresent(UIIdentifiers.whistButton(.whist)) { continue }
            if robot.tapIfPresent(UIIdentifiers.defenderModeButton(.closed)) { continue }
            if robot.playFirstPlayableHandCard(acceptanceTimeout: 0.4) { continue }
            if hold.waitForExistence(timeout: 0.5) {
                sawHold = true
                break
            }
        }

        XCTAssertTrue(sawHold, "Online play never exposed the completed-trick result hold.")
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: hold
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [gone], timeout: 3),
            .completed,
            "The online result hold should clear automatically without blocking the table."
        )
    }
}
