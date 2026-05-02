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
        let recorder = MatchScreenshotRecorder(testCase: self, app: app)

        recorder.capture(name: "01-lobby")

        robot.startLocalTable()
        robot.waitForPhase("Waiting for deal")
        recorder.capture(name: "02-waiting-for-deal")

        robot.startNextDeal()
        robot.waitForPhase("Bidding")
        recorder.capture(name: "03-bidding-east")

        robot.bid(.bid(.game(GameContract(6, .suit(.spades)))))
        robot.waitForPhase("Bidding")
        recorder.capture(name: "04-bidding-south")

        robot.bid(.pass)
        robot.waitForPhase("Bidding")
        recorder.capture(name: "05-bidding-west")

        robot.bid(.pass)
        robot.waitForPhase("Talon exchange")
        recorder.capture(name: "06-talon-exchange")
    }

    // MARK: - Human-vs-bots playthrough

    /// Drives the lobby's Quick-play CTA, then plays "You" through one full
    /// deal against two bots (pass on bid/whist, play any legal card),
    /// screenshotting every phase to /Users/sol/projects/preferans/build/screens.
    func testHumanVsBotsPlaythrough() {
        let screenDir = URL(fileURLWithPath: "/Users/sol/projects/preferans/build/screens")
        func sanitize(_ s: String) -> String {
            String(s.replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: ":", with: "")
                .replacingOccurrences(of: "/", with: "_")
                .prefix(40))
        }

        let app = XCUIApplication()
        app.launchArguments += [UITestFlags.viewerFollowsActor]
        app.launch()
        let robot = MatchUIRobot(app: app)
        let recorder = MatchScreenshotRecorder(testCase: self, app: app, outputDirectory: screenDir, filePrefix: "play")

        recorder.capture(name: "01-lobby")

        let quick = app.buttons["button.quickPlayVsBots"]
        XCTAssertTrue(quick.waitForExistence(timeout: 5), "Quick-play CTA never appeared")
        quick.tap()

        recorder.capture(name: "02-after-quickplay")

        let startDeal = app.buttons[UIIdentifiers.buttonStartDeal]
        if startDeal.waitForExistence(timeout: 3) {
            startDeal.tap()
        }
        recorder.capture(name: "03-deal-started")

        for i in 0..<60 {
            let phase = app.staticTexts[UIIdentifiers.phaseTitle].label
            recorder.capture(name: String(format: "%02d-%@", i + 4, sanitize(phase)))

            if app.otherElements[UIIdentifiers.Panel.dealFinished.rawValue].exists ||
               app.otherElements[UIIdentifiers.Panel.gameOver.rawValue].exists {
                break
            }

            if robot.tapIfPresent(UIIdentifiers.bidButton(.pass)) { continue }
            if robot.tapIfPresent(UIIdentifiers.whistButton(.pass)) { continue }
            if robot.playFirstAcceptedHandCard(for: "You", acceptanceTimeout: 0.4) { continue }
            if robot.discardFirstTwoVisibleCards() { continue }
            if robot.tapIfPresent(UIIdentifiers.buttonStartDeal) { continue }

            usleep(700_000)
        }

        recorder.capture(name: "99-final")
    }

    /// Plays a full 4-player match to pool target = 6 against three bots.
    /// Screenshots only on phase transitions + every deal-finished panel,
    /// so the artifact is one page per phase, not one per tick.
    func testHumanVsBotsFullMatchFourPlayersPoolSix() {
        let screenDir = URL(fileURLWithPath: "/Users/sol/projects/preferans/build/screens-match")
        try? FileManager.default.removeItem(at: screenDir)

        let app = XCUIApplication()
        // Pool target = 6, viewer follows actor, animations off so the
        // simulator burns less time on transitions.
        app.launchArguments += [
            UITestFlags.viewerFollowsActor,
            UITestFlags.disableAnimations,
            UITestFlags.poolTarget, "6",
        ]
        app.launch()
        let robot = MatchUIRobot(app: app)
        let recorder = MatchScreenshotRecorder(testCase: self, app: app, outputDirectory: screenDir, filePrefix: "match")
        recorder.capture(name: "01-lobby", key: robot.screenshotDeduplicationKey(), force: true, attach: false)

        // Switch lobby to 4 players, then start.
        let fourPlayers = app.buttons[UIIdentifiers.lobbyPlayerCountFour]
        XCTAssertTrue(fourPlayers.waitForExistence(timeout: 5))
        fourPlayers.tap()
        recorder.capture(name: "02-lobby-4p", key: robot.screenshotDeduplicationKey(), force: true, attach: false)
        let startTable = app.buttons[UIIdentifiers.lobbyStartLocalTable]
        XCTAssertTrue(startTable.waitForExistence(timeout: 3))
        startTable.tap()
        recorder.capture(name: "03-table-ready", key: robot.screenshotDeduplicationKey(), force: true, attach: false)

        // Drive the match: each loop iteration takes one human-side action
        // (or sleeps for bots), and snapshots phase transitions.
        let stepLimit = 800
        var dealStartCount = 0
        var sawGameOver = false
        for _ in 0..<stepLimit {
            recorder.capture(name: "tick", key: robot.screenshotDeduplicationKey(), attach: false)

            if app.otherElements[UIIdentifiers.Panel.gameOver.rawValue].exists ||
               app.staticTexts[UIIdentifiers.gameOverTitle].exists {
                sawGameOver = true
                recorder.capture(name: "match-over", key: robot.screenshotDeduplicationKey(), force: true, attach: false)
                break
            }

            // The deal-finished sheet and the action bar both expose the
            // same "advance the match" affordance under one shared
            // identifier — one tap drives the engine forward regardless of
            // which surface is currently presenting it.
            if robot.tapIfPresent(UIIdentifiers.buttonStartDeal) {
                dealStartCount += 1
                recorder.capture(name: "deal-\(dealStartCount)-started", key: robot.screenshotDeduplicationKey(), force: true, attach: false)
                continue
            }
            if robot.tapIfPresent(UIIdentifiers.bidButton(.pass)) { continue }
            if robot.tapIfPresent(UIIdentifiers.whistButton(.pass)) { continue }
            if robot.playFirstAcceptedHandCard(for: "You") { continue }
            if robot.discardFirstTwoVisibleCards() { continue }

            // Bot turn — with bot delay = 0 (animations off) the next
            // human-actionable state lands fast; keep the idle short so
            // a stalled match fails loudly within ~30 s.
            usleep(80_000)
        }

        recorder.capture(name: "99-final", key: robot.screenshotDeduplicationKey(), force: true, attach: false)
        XCTAssertTrue(sawGameOver, "Match never reached gameOver in \(stepLimit) ticks (deals started: \(dealStartCount))")
    }
}
