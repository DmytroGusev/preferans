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
        XCTAssertFalse(app.buttons[UIIdentifiers.onlineCreateRoom].exists,
                       "Inactive modes must not expose invisible actionable controls")

        robot.startLocalTable()
        robot.waitForElement(UIIdentifiers.screenGame)
        robot.waitForPhase("Ready")
        robot.waitForElement(UIIdentifiers.buttonStartDeal)
    }

    func testOnlineControlsBelongToVisibleOnlineMode() {
        let app = XCUIApplication()
        app.disableUITestAnimations()
        app.launch()
        let robot = MatchUIRobot(app: app)
        let online = app.buttons[UIIdentifiers.lobbyModeOnline]
        XCTAssertTrue(online.waitForExistence(timeout: 2) && online.isHittable)
        online.tap()
        XCTAssertFalse(app.buttons[UIIdentifiers.lobbyStartLocalTable].exists)
        robot.waitForElement(UIIdentifiers.onlineCreateRoom)
        let joinCode = app.textFields[UIIdentifiers.onlineJoinRoomCode]
        robot.revealLobbyControl(joinCode)
        XCTAssertFalse(app.buttons[UIIdentifiers.onlineJoinRoom].exists,
                       "Join appears when the player supplies a room code")
        joinCode.tap()
        joinCode.typeText("TABLE42\n")
        robot.waitForElement(UIIdentifiers.onlineJoinRoom)
        MatchScreenshotRecorder(testCase: self, app: app)
            .capture(name: "lobby-online-visible-join", force: true)
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
