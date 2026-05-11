import XCTest
import PreferansEngine

@MainActor
final class AccessibilityContractTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testLobbyAndGameExposeStableAutomationRoots() {
        let app = XCUIApplication()
        app.disableUITestAnimations()
        app.launch()
        let robot = MatchUIRobot(app: app)

        robot.waitForElement(UIIdentifiers.appRoot)
        robot.waitForElement(UIIdentifiers.screenLobby)
        robot.waitForElement(UIIdentifiers.onlineCreateRoom)
        robot.waitForElement(UIIdentifiers.onlineJoinRoomCode)
        robot.waitForElement(UIIdentifiers.onlineJoinRoom)

        robot.startLocalTable()
        robot.waitForElement(UIIdentifiers.screenGame)
        robot.waitForPhase("Ready")
        robot.waitForElement(UIIdentifiers.buttonStartDeal)
    }
}
