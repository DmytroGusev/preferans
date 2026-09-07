import XCTest
import PreferansEngine

@MainActor
final class RedesignScreenshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    /// Resolve the on-disk dump location for a screenshot bucket. Honors
    /// `PREFERANS_SCREEN_DIR` from the environment when set (bin/screens
    /// can point this at the repo's `build/` tree); otherwise falls back
    /// to a temp directory so the test still works on a fresh checkout
    /// where `/Users/sol/...` doesn't exist.
    private func screenDir(_ bucket: String) -> URL {
        let root: URL
        if let override = ProcessInfo.processInfo.environment["PREFERANS_SCREEN_DIR"], !override.isEmpty {
            root = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("preferans-screens", isDirectory: true)
        }
        return root.appendingPathComponent(bucket, isDirectory: true)
    }

    /// Captures the first slide at both the default and largest accessibility
    /// text sizes. This keeps the onboarding screen in the same fresh-render
    /// audit path as the lobby, table, and online room.
    func testCaptureOnboardingDynamicType() {
        let defaultApp = XCUIApplication()
        defaultApp.launchArguments += [
            UITestFlags.showOnboarding,
            UITestFlags.disableAnimations,
        ]
        defaultApp.pinTestLocaleEnglish()
        defaultApp.launch()

        let defaultRobot = MatchUIRobot(app: defaultApp)
        defaultRobot.waitForElement(UIIdentifiers.screenOnboarding)
        MatchScreenshotRecorder(testCase: self, app: defaultApp)
            .capture(name: "onboarding-default", force: true)
        defaultApp.terminate()

        let accessibilityApp = XCUIApplication()
        accessibilityApp.launchArguments += [
            UITestFlags.showOnboarding,
            UITestFlags.disableAnimations,
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        accessibilityApp.pinTestLocaleEnglish()
        accessibilityApp.launch()

        let accessibilityRobot = MatchUIRobot(app: accessibilityApp)
        accessibilityRobot.waitForElement(UIIdentifiers.screenOnboarding)
        MatchScreenshotRecorder(testCase: self, app: accessibilityApp)
            .capture(name: "onboarding-accessibility-xxxl", force: true)
    }

    /// Settings is a scrollable administrative surface rather than a card
    /// table. At the largest supported content size every row must remain
    /// reachable, and choosing a language must keep the app alive while it
    /// explains that the new catalog is applied on the next launch.
    func testCaptureSettingsAtAccessibilityXXXL() {
        let output = screenDir("screens-settings-accessibility")
        try? FileManager.default.removeItem(at: output)

        let app = XCUIApplication()
        app.disableUITestAnimations()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        let robot = MatchUIRobot(app: app)
        robot.waitForElement(UIIdentifiers.screenLobby)
        let settingsButton = app.buttons[UIIdentifiers.lobbySettingsButton]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 2))
        settingsButton.tap()
        robot.waitForElement(UIIdentifiers.screenSettings)

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 2) && done.isHittable)
        MatchScreenshotRecorder(
            testCase: self,
            app: app,
            outputDirectory: output,
            filePrefix: "settings"
        )
        .capture(name: "top-accessibility-xxxl", force: true, attach: false)

        let language = app.descendants(matching: .any)[UIIdentifiers.settingsLanguagePicker]
        for _ in 0..<4 where !language.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(language.isHittable, "Language must remain reachable at Accessibility XXXL")
        MatchScreenshotRecorder(
            testCase: self,
            app: app,
            outputDirectory: output,
            filePrefix: "settings"
        )
        .capture(name: "language-accessibility-xxxl", force: true, attach: false)

        language.tap()
        let russian = app.buttons["Русский"]
        XCTAssertTrue(russian.waitForExistence(timeout: 2) && russian.isHittable)
        russian.tap()

        XCTAssertTrue(app.staticTexts["Restart required"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Language will switch on next launch."].exists)
        app.alerts.buttons["Done"].tap()
        robot.waitForElement(UIIdentifiers.screenSettings)
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Launch Russian directly so catalog verification does not depend on
    /// test ordering or a second app process inside one XCUITest.
    func testCaptureSettingsRussianAtAccessibilityXXXL() {
        let output = screenDir("screens-settings-russian-accessibility")
        try? FileManager.default.removeItem(at: output)

        let app = XCUIApplication()
        app.launchArguments += [
            UITestFlags.disableAnimations,
            UITestFlags.pinLanguageRu,
            "-AppleLanguages", "(ru)",
            "-AppleLocale", "ru_RU",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        let robot = MatchUIRobot(app: app)
        robot.waitForElement(UIIdentifiers.screenLobby)
        let settingsButton = app.buttons[UIIdentifiers.lobbySettingsButton]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 2))
        settingsButton.tap()
        robot.waitForElement(UIIdentifiers.screenSettings)
        XCTAssertTrue(app.staticTexts["Внешний вид"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons[UIIdentifiers.settingsThemePicker].exists)
        MatchScreenshotRecorder(
            testCase: self,
            app: app,
            outputDirectory: output,
            filePrefix: "settings"
        )
        .capture(name: "russian-accessibility-xxxl", force: true, attach: false)
        let deleteAccount = app.buttons[UIIdentifiers.onlineDeleteAccount]
        for _ in 0..<8 where !deleteAccount.isHittable { app.swipeUp() }
        XCTAssertTrue(deleteAccount.isHittable)
        XCTAssertEqual(deleteAccount.label, "Удалить онлайн-аккаунт")
        MatchScreenshotRecorder(testCase: self, app: app, outputDirectory: output, filePrefix: "settings")
            .capture(name: "russian-account-accessibility-xxxl", force: true, attach: false)
    }

    /// Normal iPad keeps the dedicated navigation/setup columns, while
    /// Accessibility text stacks both regions on every device so controls are
    /// never squeezed into the tablet's narrow navigation column.
    func testCaptureLobbyDeviceLayouts() {
        let output = screenDir("screens-lobby-layout")
        try? FileManager.default.removeItem(at: output)

        let defaultApp = XCUIApplication()
        defaultApp.launchArguments += [UITestFlags.disableAnimations]
        defaultApp.pinTestLocaleEnglish()
        defaultApp.launch()

        let defaultNavigation = defaultApp.descendants(matching: .any)[UIIdentifiers.lobbyNavigationRegion]
        let defaultMode = defaultApp.descendants(matching: .any)[UIIdentifiers.lobbyModeRegion]
        XCTAssertTrue(defaultNavigation.waitForExistence(timeout: 5))
        XCTAssertTrue(defaultMode.waitForExistence(timeout: 2))
        if defaultApp.windows.firstMatch.frame.width >= 700 {
            XCTAssertLessThan(defaultNavigation.frame.maxX, defaultMode.frame.minX)
        } else {
            XCTAssertLessThan(defaultNavigation.frame.maxY, defaultMode.frame.minY)
        }
        MatchScreenshotRecorder(
            testCase: self,
            app: defaultApp,
            outputDirectory: output,
            filePrefix: "lobby"
        )
        .capture(name: "default", force: true, attach: false)
        defaultApp.terminate()

        let accessibilityApp = XCUIApplication()
        accessibilityApp.launchArguments += [
            UITestFlags.disableAnimations,
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        accessibilityApp.pinTestLocaleEnglish()
        accessibilityApp.launch()

        let accessibleNavigation = accessibilityApp.descendants(matching: .any)[UIIdentifiers.lobbyNavigationRegion]
        let accessibleMode = accessibilityApp.descendants(matching: .any)[UIIdentifiers.lobbyModeRegion]
        let accessibleLocalMode = accessibilityApp.buttons[UIIdentifiers.lobbyModeLocal]
        let accessibleOnlineMode = accessibilityApp.buttons[UIIdentifiers.lobbyModeOnline]
        XCTAssertTrue(accessibleNavigation.waitForExistence(timeout: 5))
        XCTAssertTrue(accessibleMode.waitForExistence(timeout: 2))
        XCTAssertTrue(accessibleLocalMode.waitForExistence(timeout: 2))
        XCTAssertTrue(accessibleOnlineMode.waitForExistence(timeout: 2))
        XCTAssertLessThan(
            accessibleNavigation.frame.maxY,
            accessibleMode.frame.minY,
            "Accessibility text should stack the lobby regions instead of squeezing either column"
        )
        XCTAssertLessThan(
            accessibleLocalMode.frame.maxY,
            accessibleOnlineMode.frame.minY,
            "Accessibility text should stack the play-mode choices instead of clipping their labels"
        )
        MatchScreenshotRecorder(
            testCase: self,
            app: accessibilityApp,
            outputDirectory: output,
            filePrefix: "lobby"
        )
        .capture(name: "accessibility-xxxl", force: true, attach: false)

        let robot = MatchUIRobot(app: accessibilityApp)
        robot.openTableOptions()
        let price = accessibilityApp.descendants(matching: .any)[UIIdentifiers.matchRaspasyPrice]
        robot.revealLobbyControl(price)
        price.tap()
        let progression = accessibilityApp.buttons["1–2–4"]
        XCTAssertTrue(progression.waitForExistence(timeout: 2) && progression.isHittable,
                      "Every progression must be fully readable and selectable at large text")
        progression.tap()
        robot.revealLobbyControl(price)
        XCTAssertTrue(accessibilityApp.buttons[UIIdentifiers.lobbyStartLocalTable].isHittable)
        MatchScreenshotRecorder(testCase: self, app: accessibilityApp,
                                outputDirectory: output, filePrefix: "lobby")
            .capture(name: "options-accessibility-xxxl", force: true, attach: false)
    }

    /// Accessibility text deliberately replaces the wide iPad auction grid
    /// with the same scrollable rail used by iPhone. Capture the real table on
    /// both devices and keep the opening actions fully visible and tappable.
    func testCaptureTableAuctionAtAccessibilityXXXL() {
        let output = screenDir("screens-table-accessibility")
        try? FileManager.default.removeItem(at: output)

        let app = XCUIApplication()
        app.configureForMatchScript(
            "game1",
            extra: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityXXXL",
            ]
        )
        app.launch()

        let robot = MatchUIRobot(app: app)
        robot.startLocalTable()
        robot.waitForPhase("Ready")
        robot.startNextDeal()
        robot.waitForPhase("Bidding")

        let rail = app.descendants(matching: .any)[UIIdentifiers.actionChoiceRailCompact]
        let pass = app.buttons[UIIdentifiers.bidButton(.pass)]
        let sixSpadesCall = BidCall.bid(.game(GameContract(6, .suit(.spades))))
        let sixSpades = app.buttons[UIIdentifiers.bidButton(sixSpadesCall)]
        XCTAssertTrue(rail.waitForExistence(timeout: 2))
        XCTAssertTrue(pass.waitForExistence(timeout: 2) && pass.isHittable)
        XCTAssertTrue(sixSpades.waitForExistence(timeout: 2) && sixSpades.isHittable)
        XCTAssertGreaterThanOrEqual(pass.frame.height, 44)
        XCTAssertGreaterThanOrEqual(sixSpades.frame.height, 44)
        XCTAssertEqual(
            pass.frame.midY,
            sixSpades.frame.midY,
            accuracy: 2,
            "Accessibility text should use one natural-height action row"
        )

        MatchScreenshotRecorder(
            testCase: self,
            app: app,
            outputDirectory: output,
            filePrefix: "table-auction"
        )
        .capture(name: "accessibility-xxxl", force: true, attach: false)

        robot.bid(.bid(.game(GameContract(10, .suit(.spades)))))
        robot.waitForPhase("Bidding")
        XCTAssertEqual(robot.currentViewer(), "south")
    }

    /// The settlement control uses deliberately different compositions:
    /// stacked actions on iPhone and a bounded action column on iPad.
    func testCaptureSettlementComposerDeviceLayout() {
        let output = screenDir("screens-settlement")
        try? FileManager.default.removeItem(at: output)

        let app = XCUIApplication()
        app.launchArguments += [
            UITestFlags.previewSettlement,
            UITestFlags.disableAnimations,
        ]
        app.pinTestLocaleEnglish()
        app.launch()

        let root = app.descendants(matching: .any)[UIIdentifiers.screenSettlementPreview]
        XCTAssertTrue(root.waitForExistence(timeout: 5), "Settlement preview never appeared")
        let split = app.descendants(matching: .any)
            .matching(identifier: UIIdentifiers.settlementSplitControl)
            .firstMatch
        let offer = app.buttons[UIIdentifiers.buttonOfferSettlement].firstMatch
        XCTAssertTrue(split.waitForExistence(timeout: 2))
        XCTAssertTrue(offer.waitForExistence(timeout: 2))

        if app.windows.firstMatch.frame.width >= 700 {
            XCTAssertGreaterThan(
                offer.frame.minX,
                split.frame.maxX,
                "iPad should place settlement actions in a dedicated trailing column"
            )
        } else {
            XCTAssertGreaterThan(
                offer.frame.minY,
                split.frame.maxY,
                "iPhone should stack settlement actions beneath the split control"
            )
        }

        MatchScreenshotRecorder(
            testCase: self,
            app: app,
            outputDirectory: output,
            filePrefix: "settlement"
        )
        .capture(name: "device-layout", force: true)
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
        let recorder = MatchScreenshotRecorder(testCase: self, app: app)

        recorder.capture(name: "01-lobby")

        robot.startLocalTable()
        robot.waitForPhase("Ready")
        recorder.capture(name: "02-waiting-for-deal")

        robot.startNextDeal()
        robot.waitForPhase("Bidding")
        let sixNoTrump = app.buttons[
            UIIdentifiers.bidButton(.bid(.game(GameContract(6, .noTrump))))
        ]
        XCTAssertTrue(
            sixNoTrump.waitForExistence(timeout: 1) && sixNoTrump.isHittable,
            "The complete opening bid level must be immediately reachable without scrolling"
        )
        let tenNoTrump = app.buttons[
            UIIdentifiers.bidButton(.bid(.game(GameContract(10, .noTrump))))
        ]
        if app.windows.firstMatch.frame.width >= 900 {
            XCTAssertTrue(
                app.descendants(matching: .any)[UIIdentifiers.actionChoiceGridRegular].exists,
                "A wide iPad table should expose bidding in its full grid"
            )
            XCTAssertTrue(
                tenNoTrump.exists && tenNoTrump.isHittable,
                "A wide iPad table should expose the full auction without horizontal scrolling"
            )
        } else {
            XCTAssertTrue(
                app.descendants(matching: .any)[UIIdentifiers.actionChoiceRailCompact].exists,
                "A phone or narrow iPad table should retain the readable two-row bidding rail"
            )
            XCTAssertFalse(
                tenNoTrump.isHittable,
                "A narrow table should not compress every auction level into its available width"
            )
        }
        recorder.capture(name: "03-bidding-east")

        robot.bid(.bid(.game(GameContract(6, .suit(.spades)))))
        robot.waitForPhase("Bidding")
        recorder.capture(name: "04-bidding-south")

        robot.bid(.pass)
        robot.waitForPhase("Bidding")
        recorder.capture(name: "05-bidding-west")

        robot.bid(.pass)
        robot.waitForPhase("Prikup")
        recorder.capture(name: "06-talon-exchange")
    }

    // MARK: - Human-vs-bots playthrough

    /// Starts a table and keeps the same human seat through a full deal
    /// against two bots (pass on bids, whist on defense, play legal cards),
    /// screenshotting every phase. PNGs land in `$PREFERANS_SCREEN_DIR/screens`
    /// when set, otherwise under the temp directory.
    func testHumanVsBotsPlaythrough() {
        let screenDir = screenDir("screens")
        // Start from an empty bucket like the match/pulka tests do —
        // otherwise frames from an older run interleave with this one's
        // and the folder lies about what the current code renders.
        try? FileManager.default.removeItem(at: screenDir)
        func sanitize(_ s: String) -> String {
            String(s.replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: ":", with: "")
                .replacingOccurrences(of: "/", with: "_")
                .prefix(40))
        }

        let app = XCUIApplication()
        app.pinTestLocaleEnglish()
        // Auto-advance trick results and run bots fast so the playthrough
        // actually progresses through tricks (and so the captured "Play"
        // frames show real, populated tricks rather than freezing on the
        // opening lead).
        app.launchArguments += [
            UITestFlags.skipTapToAdvance,
            UITestFlags.fastBotDelay,
            UITestFlags.disableAnimations,
            UITestFlags.dealSeed, "20260907",
            UITestFlags.firstDealer, "Trinity",
        ]
        app.launch()
        let robot = MatchUIRobot(app: app)
        let recorder = MatchScreenshotRecorder(testCase: self, app: app, outputDirectory: screenDir, filePrefix: "play")

        recorder.capture(name: "01-lobby")

        let sitDown = app.buttons[UIIdentifiers.lobbyStartLocalTable]
        XCTAssertTrue(sitDown.waitForExistence(timeout: 5), "Sit-down CTA never appeared")
        sitDown.tap()

        recorder.capture(name: "02-after-quickplay")

        let startDeal = app.buttons[UIIdentifiers.buttonStartDeal]
        if startDeal.waitForExistence(timeout: 3) {
            startDeal.tap()
        }
        robot.waitForPhase("Bidding")
        recorder.capture(name: "03-deal-started")

        var completedDeal = false
        var humanCardsPlayed = 0
        let human = robot.currentViewer()
        XCTAssertEqual(human, "Neo")
        for i in 0..<60 {
            let phase = app.staticTexts[UIIdentifiers.phaseTitle].label
            let trickMilestone = [0, 1, 5, 9, 10].last { $0 <= humanCardsPlayed } ?? 0
            recorder.capture(
                name: String(format: "%02d-%@", i + 4, sanitize(phase)),
                key: robot.screenshotDeduplicationKey(dealNumber: 1) + "|humanCards=\(trickMilestone)",
                attach: false
            )

            if app.otherElements[UIIdentifiers.Panel.dealFinished.rawValue].exists ||
               app.otherElements[UIIdentifiers.Panel.gameOver.rawValue].exists ||
               app.buttons[UIIdentifiers.buttonStartDeal].exists {
                completedDeal = true
                print("[playthrough] completed one deal after \(i + 1) bounded iterations")
                break
            }

            XCTAssertEqual(robot.currentViewer(), human, "The human must never adopt a bot's hand")

            if robot.tapIfPresent(UIIdentifiers.bidButton(.pass)) { continue }
            if robot.tapIfPresent(UIIdentifiers.whistButton(.whist)) { continue }
            if robot.tapIfPresent(UIIdentifiers.defenderModeButton(.closed)) { continue }
            if robot.playFirstPlayableHandCard(acceptanceTimeout: 0.4) {
                humanCardsPlayed += 1
                print("[playthrough] human played card \(humanCardsPlayed)/10")
                continue
            }
            if robot.discardFirstTwoVisibleCards() { continue }

            // Nothing actionable — a bot is on the clock. Wait for the phase
            // label to move instead of sleeping blindly: same worst-case
            // bound, but returns the moment the bot acts.
            let phaseElement = app.staticTexts[UIIdentifiers.phaseTitle]
            let phaseBefore = robot.labelIfExists(UIIdentifiers.phaseTitle)
            _ = XCTWaiter().wait(
                for: [XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "label != %@", phaseBefore),
                    object: phaseElement
                )],
                timeout: 0.7
            )
        }

        XCTAssertTrue(completedDeal, "The one-deal playthrough exhausted its 60-iteration bound")
        XCTAssertEqual(humanCardsPlayed, 10, "A human playthrough must play the human's entire hand")
        recorder.capture(name: "99-final")
    }

    /// A strategic bot action should explain itself briefly on the felt and
    /// remain available in the activity log after the toast fades. The test
    /// always passes as the human so one of the two bots must own the auction.
    func testBotDecisionInsightAndActivityLog() {
        let screenDir = screenDir("screens-bot-insights")
        try? FileManager.default.removeItem(at: screenDir)

        let app = XCUIApplication()
        app.pinTestLocaleEnglish()
        app.launchArguments += [
            UITestFlags.disableAnimations,
            UITestFlags.fastBotDelay,
            UITestFlags.skipTapToAdvance,
        ]
        app.launch()
        let robot = MatchUIRobot(app: app)
        let recorder = MatchScreenshotRecorder(
            testCase: self,
            app: app,
            outputDirectory: screenDir,
            filePrefix: "bot-insight"
        )

        let sitDown = app.buttons[UIIdentifiers.lobbyStartLocalTable]
        XCTAssertTrue(sitDown.waitForExistence(timeout: 5))
        sitDown.tap()
        XCTAssertTrue(app.buttons[UIIdentifiers.buttonStartDeal].waitForExistence(timeout: 3))
        app.buttons[UIIdentifiers.buttonStartDeal].tap()

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
        XCTAssertTrue(sawInsight, "No bot decision explanation appeared after the human passed")
        recorder.capture(name: "01-table-explanation", force: true, attach: false)

        let overflow = app.buttons[UIIdentifiers.overflowMenu]
        XCTAssertTrue(overflow.waitForExistence(timeout: 3))
        overflow.tap()
        let activity = app.buttons[UIIdentifiers.buttonActivityLog]
        XCTAssertTrue(activity.waitForExistence(timeout: 2))
        activity.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)[UIIdentifiers.Panel.eventLog.rawValue]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)[UIIdentifiers.botInsightEntry(index: 0)]
                .waitForExistence(timeout: 3),
            "Bot explanation was not retained in the activity log"
        )
        recorder.capture(name: "02-activity-log-notes", force: true, attach: false)
    }

    /// Captures the 4-player scoresheet immediately after sit-down so we
    /// can eyeball the diamond Pulka-diagram geometry. No deals are
    /// played — the diagram lays out on all-zero balances, which is
    /// enough to verify corner positions, outline closure, and that the
    /// top/bottom cards don't collide at the sidebar/sheet widths.
    func testCaptureFourPlayerPulkaDiagram() {
        let screenDir = screenDir("screens-pulka")
        try? FileManager.default.removeItem(at: screenDir)

        let app = XCUIApplication()
        app.pinTestLocaleEnglish()
        app.launchArguments += [
            UITestFlags.disableAnimations,
            UITestFlags.fastBotDelay,
        ]
        app.launch()
        let recorder = MatchScreenshotRecorder(
            testCase: self,
            app: app,
            outputDirectory: screenDir,
            filePrefix: "pulka"
        )

        MatchUIRobot(app: app).selectPlayerCount(4)
        recorder.capture(name: "01-lobby-4p", force: true, attach: false)

        let startTable = app.buttons[UIIdentifiers.lobbyStartLocalTable]
        XCTAssertTrue(startTable.waitForExistence(timeout: 3))
        startTable.tap()
        recorder.capture(name: "02-table-ready", force: true, attach: false)

        let scoreButton = app.buttons[UIIdentifiers.buttonScoreSheet]
        XCTAssertTrue(scoreButton.waitForExistence(timeout: 5))
        scoreButton.tap()
        let scorePanel = app.otherElements[UIIdentifiers.Panel.score.rawValue]
        XCTAssertTrue(scorePanel.waitForExistence(timeout: 5))
        recorder.capture(name: "03-scoresheet-square", force: true, attach: false)

        let dismiss = app.buttons[UIIdentifiers.buttonDismissSheet]
        if dismiss.waitForExistence(timeout: 3) { dismiss.tap() }
        recorder.capture(name: "04-after-dismiss", force: true, attach: false)
    }

    /// Plays a full 4-player match to pool target = 6 against three bots.
    /// Screenshots only on phase transitions + every deal-finished panel,
    /// so the artifact is one page per phase, not one per tick.
    func testHumanVsBotsFullMatchFourPlayersPoolSix() {
        let screenDir = screenDir("screens-match")
        try? FileManager.default.removeItem(at: screenDir)

        let app = XCUIApplication()
        // Pool target = 6, viewer follows actor, animations off so the
        // simulator burns less time on transitions.
        app.pinTestLocaleEnglish()
        app.launchArguments += [
            UITestFlags.viewerFollowsActor,
            UITestFlags.disableAnimations,
            UITestFlags.fastBotDelay,
            UITestFlags.skipTapToAdvance,
            UITestFlags.poolTarget, "6",
        ]
        app.launch()
        let robot = MatchUIRobot(app: app)
        let recorder = MatchScreenshotRecorder(testCase: self, app: app, outputDirectory: screenDir, filePrefix: "match")
        recorder.capture(name: "01-lobby", key: robot.screenshotDeduplicationKey(dealNumber: 0), force: true, attach: false)

        // Switch lobby to 4 players, then start.
        robot.selectPlayerCount(4)
        recorder.capture(name: "02-lobby-4p", key: robot.screenshotDeduplicationKey(dealNumber: 0), force: true, attach: false)
        let startTable = app.buttons[UIIdentifiers.lobbyStartLocalTable]
        XCTAssertTrue(startTable.waitForExistence(timeout: 3))
        startTable.tap()
        recorder.capture(name: "03-table-ready", key: robot.screenshotDeduplicationKey(dealNumber: 0), force: true, attach: false)

        // Drive the match: each loop iteration takes one human-side action
        // (or briefly waits for bots), and snapshots phase transitions.
        let stepLimit = 320
        var dealStartCount = 0
        var sawGameOver = false
        var lastProgress = ""
        for step in 0..<stepLimit {
            let progress = [
                "step=\(step)",
                "deal=\(dealStartCount)",
                "phase=\(robot.labelIfExists(UIIdentifiers.phaseTitle))",
                "viewer=\(robot.labelIfExists(UIIdentifiers.viewerLabel))",
                "message=\(robot.labelIfExists(UIIdentifiers.phaseMessage))"
            ].joined(separator: " ")
            if progress != lastProgress {
                print("[match-ui] \(progress)")
                lastProgress = progress
            }
            recorder.capture(name: "tick", key: robot.screenshotDeduplicationKey(dealNumber: dealStartCount), attach: false)

            if app.otherElements[UIIdentifiers.Panel.gameOver.rawValue].exists ||
               app.staticTexts[UIIdentifiers.gameOverTitle].exists {
                sawGameOver = true
                recorder.capture(name: "match-over", key: robot.screenshotDeduplicationKey(dealNumber: dealStartCount), force: true, attach: false)
                break
            }

            // The deal-finished sheet and the action bar both expose the
            // same "advance the match" affordance under one shared
            // identifier — one tap drives the engine forward regardless of
            // which surface is currently presenting it.
            if robot.tapIfPresent(UIIdentifiers.buttonStartDeal) {
                dealStartCount += 1
                recorder.capture(name: "deal-\(dealStartCount)-started", key: robot.screenshotDeduplicationKey(dealNumber: dealStartCount), force: true, attach: false)
                continue
            }
            if robot.tapIfPresent(UIIdentifiers.bidButton(.pass)) { continue }
            if robot.tapIfPresent(UIIdentifiers.whistButton(.pass)) { continue }
            // Mandatory-whist table rules (for example a 10-trick game)
            // omit pass, so take the forced call instead of idling out.
            if robot.tapIfPresent(UIIdentifiers.whistButton(.whist)) { continue }
            // Seat-agnostic: with viewerFollowsActor the interactive hand
            // changes owner every trick, and a hard-coded display name
            // ("Anya") silently never matches the current roster — the
            // match then stalls forever on the first real trick.
            if robot.playFirstPlayableHandCard(acceptanceTimeout: 0.12) { continue }
            if robot.discardFirstTwoVisibleCards() { continue }

            // Bot turn — with bot delay = 0 (animations off) the next
            // human-actionable state lands fast; keep the idle short so
            // a stalled match fails loudly within ~30 s.
            usleep(40_000)
        }

        recorder.capture(name: "99-final", key: robot.screenshotDeduplicationKey(dealNumber: dealStartCount), force: true, attach: false)
        XCTAssertTrue(sawGameOver, "Match never reached gameOver in \(stepLimit) ticks. Last progress: \(lastProgress)")
    }
}
