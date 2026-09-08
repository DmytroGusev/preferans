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
        let noTrump = app.buttons[UIIdentifiers.bidButton(.bid(.game(GameContract(6, .noTrump))))]
        XCTAssertTrue(noTrump.label.contains("NT"), "A no-trump bid must include its strain")

        print("THEME \(theme): exchange, declaration, and open defense")
        let contract = GameContract(6, .suit(.spades))
        robot.bid(.bid(.game(contract)))
        robot.bid(.pass)
        robot.bid(.pass)
        robot.waitForPhase("Prikup")
        recorder.capture(name: "theme-\(theme)-talon-choice", force: true)
        robot.takeTalon()
        recorder.capture(name: "theme-\(theme)-discard", force: true)
        XCTAssertTrue(robot.discardFirstTwoVisibleCards())
        robot.waitForPhase("Contract")
        recorder.capture(name: "theme-\(theme)-contract", force: true)
        robot.declareContract(contract)
        robot.waitForPhase("Whist")
        recorder.capture(name: "theme-\(theme)-whist", force: true)
        robot.whist(.whist)
        robot.whist(.pass)
        robot.waitForPhase("Defense")
        recorder.capture(name: "theme-\(theme)-defender-mode", force: true)
        robot.defenderMode(.open)
        robot.waitForPhase("Play")
        recorder.capture(name: "theme-\(theme)-open-hands", force: true)

        print("THEME \(theme): settlement and results")
        app.buttons[UIIdentifiers.buttonOfferSettlement].tap()
        XCTAssertTrue(app.buttons[UIIdentifiers.buttonSubmitSettlement].waitForExistence(timeout: 2))
        recorder.capture(name: "theme-\(theme)-settlement-draft", force: true)
        app.buttons[UIIdentifiers.buttonSubmitSettlement].tap()
        XCTAssertTrue(app.buttons[UIIdentifiers.buttonAcceptSettlement].waitForExistence(timeout: 2))
        recorder.capture(name: "theme-\(theme)-settlement-response", force: true)
        app.buttons[UIIdentifiers.buttonAcceptSettlement].tap()
        robot.waitForPhase("Deal complete")
        recorder.capture(name: "theme-\(theme)-result", force: true)
        app.buttons[UIIdentifiers.dealInitialHandsToggle].tap()
        recorder.capture(name: "theme-\(theme)-opening-hands", force: true)
        app.buttons[UIIdentifiers.dealInitialHandsToggle].tap()

        print("THEME \(theme): scores, activity, and rules")
        app.buttons[UIIdentifiers.buttonScoreSheet].tap()
        XCTAssertTrue(app.navigationBars["Scoresheet"].waitForExistence(timeout: 2))
        recorder.capture(name: "theme-\(theme)-scoresheet", force: true)
        app.buttons[UIIdentifiers.buttonDismissSheet].tap()
        app.buttons[UIIdentifiers.overflowMenu].tap()
        app.buttons[UIIdentifiers.buttonActivityLog].tap()
        XCTAssertTrue(app.descendants(matching: .any)[UIIdentifiers.Panel.eventLog.rawValue].waitForExistence(timeout: 2))
        recorder.capture(name: "theme-\(theme)-activity", force: true)
        app.buttons[UIIdentifiers.buttonDismissSheet].tap()
        app.buttons[UIIdentifiers.overflowMenu].tap()
        app.buttons[UIIdentifiers.buttonRulesReference].tap()
        XCTAssertTrue(app.descendants(matching: .any)[UIIdentifiers.conventionLegendSheet].waitForExistence(timeout: 2))
        recorder.capture(name: "theme-\(theme)-rules", force: true)
        app.swipeUp()
        recorder.capture(name: "theme-\(theme)-rules-scrolled", force: true)
        app.buttons[UIIdentifiers.buttonDismissSheet].tap()
        robot.waitForPhase("Deal complete")
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
        let scroll = app.scrollViews[UIIdentifiers.screenThemeGallery]
        func isFullyVisible() -> Bool {
            guard element.exists, element.isHittable, scroll.exists else { return false }
            let bounds = scroll.frame.insetBy(dx: 0, dy: 8)
            return element.frame.minY >= bounds.minY && element.frame.maxY <= bounds.maxY
        }
        for _ in 0..<8 where !isFullyVisible() {
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                .press(forDuration: 0.01, thenDragTo:
                    scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)))
        }
        XCTAssertTrue(isFullyVisible(), "The selected theme's artwork and name must both be visible")
    }
}
