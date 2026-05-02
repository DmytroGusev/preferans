import XCTest
import PreferansEngine

@MainActor
final class RedesignScreenshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    /// Drives the lobby -> waiting-for-deal -> bidding -> talon-exchange flow,
    /// snapshotting at each state so a human can eyeball the felt redesign.
    func testCaptureRedesignScreens() {
        let app = XCUIApplication()
        // Animations are part of what we're capturing; opt out of the
        // speed-focused default that disables them for taps-only tests.
        app.configureForMatchScript("game1", disableAnimations: false)
        app.launch()

        let robot = MatchUIRobot(app: app)

        snapshot(app, name: "01-lobby")

        robot.startLocalTable()
        robot.waitForPhase("Waiting for deal")
        snapshot(app, name: "02-waiting-for-deal")

        robot.startNextDeal()
        robot.waitForPhase("Bidding")
        snapshot(app, name: "03-bidding-east")

        robot.bid(.bid(.game(GameContract(6, .suit(.spades)))))
        robot.waitForPhase("Bidding")
        snapshot(app, name: "04-bidding-south")

        robot.bid(.pass)
        robot.waitForPhase("Bidding")
        snapshot(app, name: "05-bidding-west")

        robot.bid(.pass)
        robot.waitForPhase("Talon exchange")
        snapshot(app, name: "06-talon-exchange")
    }

    private func snapshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
