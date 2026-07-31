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

    func testSettingsExposeStableLanguageControl() {
        let app = XCUIApplication()
        app.disableUITestAnimations()
        app.launch()
        let robot = MatchUIRobot(app: app)

        robot.waitForElement(UIIdentifiers.screenLobby)
        let settingsButton = app.buttons[UIIdentifiers.lobbySettingsButton]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3))
        settingsButton.tap()

        robot.waitForElement(UIIdentifiers.screenSettings)
        robot.waitForElement(UIIdentifiers.settingsLanguagePicker)
        let deleteAccount = app.buttons[UIIdentifiers.onlineDeleteAccount]
        XCTAssertTrue(deleteAccount.waitForExistence(timeout: 3))
        XCTAssertTrue(deleteAccount.isEnabled, "Lobby settings must expose server-backed account deletion")
        deleteAccount.tap()
        XCTAssertTrue(
            app.staticTexts["Delete online account?"].waitForExistence(timeout: 3),
            "Permanent deletion consequences were not presented"
        )
        app.buttons["Cancel"].tap()
    }
}
