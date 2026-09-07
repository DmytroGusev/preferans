import XCTest
import PreferansEngine

@MainActor
final class ThemeUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testClubhouseScreens() { captureTheme("clubhouse") }
    func testMidnightScreens() { captureTheme("midnight") }
    func testAubergineScreens() { captureTheme("aubergine") }
    func testGraphiteScreens() { captureTheme("graphite") }
    func testParchmentScreens() { captureTheme("parchment") }
    func testNordicScreens() { captureTheme("nordic") }

    private func captureTheme(_ theme: String) {
        let app = XCUIApplication()
        app.configureForMatchScript("game1", extra: [UITestFlags.theme, theme])
        app.launch()
        let robot = MatchUIRobot(app: app)
        let recorder = MatchScreenshotRecorder(testCase: self, app: app)
        robot.waitForElement(UIIdentifiers.screenLobby)
        recorder.capture(name: "theme-\(theme)-lobby", force: true)
        print("THEME \(theme): settings and gallery")
        app.buttons[UIIdentifiers.lobbySettingsButton].tap()
        robot.waitForElement(UIIdentifiers.screenSettings)
        recorder.capture(name: "theme-\(theme)-settings", force: true)
        app.buttons[UIIdentifiers.settingsThemePicker].tap()
        robot.waitForElement(UIIdentifiers.screenThemeGallery)
        let option = app.buttons[UIIdentifiers.themeOption(theme)]
        reveal(option, in: app)
        XCTAssertEqual(option.value as? String, "Selected")
        recorder.capture(name: "theme-\(theme)-gallery", force: true)
        app.navigationBars["Table themes"].buttons["BackButton"].tap()
        app.buttons[UIIdentifiers.buttonDismissSheet].tap()
        print("THEME \(theme): ready and auction")
        robot.startLocalTable()
        robot.waitForPhase("Ready")
        recorder.capture(name: "theme-\(theme)-ready", force: true)
        robot.startNextDeal()
        robot.waitForPhase("Bidding")
        recorder.capture(name: "theme-\(theme)-auction", force: true)
        XCTAssertTrue(app.buttons[UIIdentifiers.bidButton(.pass)].isHittable)
    }

    func testThemeSwitchPreservesLiveDealAndPersistsOnRelaunch() {
        let app = XCUIApplication()
        app.configureForMatchScript("game1", extra: [UITestFlags.theme, "clubhouse"])
        app.launch()
        let robot = MatchUIRobot(app: app)
        robot.startLocalTable()
        robot.startNextDeal()
        robot.waitForPhase("Bidding")
        robot.bid(.bid(.game(GameContract(6, .suit(.spades)))))
        let previousPhaseMessage = app.staticTexts[UIIdentifiers.phaseMessage].label
        print("THEME live switch: opening settings during the second bidder's turn")
        app.buttons[UIIdentifiers.overflowMenu].tap()
        app.buttons["Settings"].tap()
        app.buttons[UIIdentifiers.settingsThemePicker].tap()
        let parchment = app.buttons[UIIdentifiers.themeOption("parchment")]
        reveal(parchment, in: app)
        parchment.tap()
        XCTAssertEqual(parchment.value as? String, "Selected")
        MatchScreenshotRecorder(testCase: self, app: app)
            .capture(name: "theme-live-switch-gallery", force: true)
        app.navigationBars["Table themes"].buttons["BackButton"].tap()
        app.buttons[UIIdentifiers.buttonDismissSheet].tap()
        robot.waitForPhase("Bidding")
        XCTAssertEqual(app.staticTexts[UIIdentifiers.phaseMessage].label, previousPhaseMessage)
        // The first bid remains in the auction: two passes must advance the
        // existing deal into talon exchange instead of starting a new auction.
        robot.bid(.pass)
        robot.bid(.pass)
        robot.waitForPhase("Prikup")
        MatchScreenshotRecorder(testCase: self, app: app)
            .capture(name: "theme-live-switch-preserved-talon", force: true)
        app.terminate()
        if let index = app.launchArguments.firstIndex(of: UITestFlags.theme) {
            app.launchArguments.removeSubrange(index...index + 1)
        }
        app.launch()
        robot.waitForElement(UIIdentifiers.screenLobby)
        app.buttons[UIIdentifiers.lobbySettingsButton].tap()
        app.buttons[UIIdentifiers.settingsThemePicker].tap()
        let persisted = app.buttons[UIIdentifiers.themeOption("parchment")]
        reveal(persisted, in: app)
        XCTAssertEqual(persisted.value as? String, "Selected")
        print("THEME live switch: deal retained and preference survived relaunch")
    }

    func testGallerySupportsLargestText() {
        let app = XCUIApplication()
        app.disableUITestAnimations()
        app.launchArguments += [UITestFlags.theme, "graphite",
                                "-UIPreferredContentSizeCategoryName",
                                "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let robot = MatchUIRobot(app: app)
        robot.waitForElement(UIIdentifiers.screenLobby)
        app.buttons[UIIdentifiers.lobbySettingsButton].tap()
        app.buttons[UIIdentifiers.settingsThemePicker].tap()
        robot.waitForElement(UIIdentifiers.screenThemeGallery)
        let first = app.buttons[UIIdentifiers.themeOption("clubhouse")]
        let second = app.buttons[UIIdentifiers.themeOption("midnight")]
        XCTAssertTrue(first.exists)
        XCTAssertLessThanOrEqual(first.frame.maxY, second.frame.minY,
                                 "Large text must use one readable column")
        let recorder = MatchScreenshotRecorder(testCase: self, app: app)
        recorder.capture(name: "theme-gallery-largest-text-top", force: true)
        let nordic = app.buttons[UIIdentifiers.themeOption("nordic")]
        reveal(nordic, in: app)
        nordic.tap()
        XCTAssertEqual(nordic.value as? String, "Selected")
        recorder.capture(name: "theme-gallery-largest-text-selected", force: true)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
}
