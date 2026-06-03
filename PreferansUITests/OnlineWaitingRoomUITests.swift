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
    }
}
