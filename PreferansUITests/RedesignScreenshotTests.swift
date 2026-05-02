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

    // MARK: - Human-vs-bots playthrough

    /// Drives the lobby's Quick-play CTA, then plays "You" through one full
    /// deal against two bots (pass on bid/whist, play any legal card),
    /// screenshotting every phase to /Users/sol/projects/preferans/build/screens.
    func testHumanVsBotsPlaythrough() {
        let screenDir = URL(fileURLWithPath: "/Users/sol/projects/preferans/build/screens")
        try? FileManager.default.createDirectory(at: screenDir, withIntermediateDirectories: true)
        var step = 0
        func snap(_ app: XCUIApplication, _ name: String) {
            let img = app.screenshot()
            let url = screenDir.appendingPathComponent(String(format: "play-%03d-%@.png", step, name))
            try? img.pngRepresentation.write(to: url)
            step += 1
            let attachment = XCTAttachment(screenshot: img)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        func sanitize(_ s: String) -> String {
            String(s.replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: ":", with: "")
                .replacingOccurrences(of: "/", with: "_")
                .prefix(40))
        }
        func tapIfPresent(_ app: XCUIApplication, _ id: String) -> Bool {
            let b = app.buttons[id]
            guard b.exists, b.isHittable else { return false }
            b.tap()
            return true
        }
        func tryPlayHandCard(_ app: XCUIApplication) -> Bool {
            let predicate = NSPredicate(format: "identifier BEGINSWITH 'card.hand.You.'")
            let cards = app.buttons.matching(predicate)
            guard cards.count > 0 else { return false }
            for i in 0..<cards.count {
                let card = cards.element(boundBy: i)
                if card.exists, card.isHittable {
                    card.tap()
                    if app.staticTexts[UIIdentifiers.errorBanner].waitForExistence(timeout: 0.4) {
                        continue
                    }
                    return true
                }
            }
            return false
        }
        func tryDiscardTwo(_ app: XCUIApplication) -> Bool {
            let predicate = NSPredicate(format: "identifier BEGINSWITH 'card.discardSelect.'")
            let cards = app.buttons.matching(predicate)
            guard cards.count >= 2 else { return false }
            cards.element(boundBy: 0).tap()
            cards.element(boundBy: 1).tap()
            return tapIfPresent(app, UIIdentifiers.buttonDiscardSelected)
        }

        let app = XCUIApplication()
        app.launchArguments += [UITestFlags.viewerFollowsActor]
        app.launch()

        snap(app, "01-lobby")

        let quick = app.buttons["button.quickPlayVsBots"]
        XCTAssertTrue(quick.waitForExistence(timeout: 5), "Quick-play CTA never appeared")
        quick.tap()

        snap(app, "02-after-quickplay")

        let startDeal = app.buttons[UIIdentifiers.buttonStartDeal]
        if startDeal.waitForExistence(timeout: 3) {
            startDeal.tap()
        }
        snap(app, "03-deal-started")

        for i in 0..<60 {
            let phase = app.staticTexts[UIIdentifiers.phaseTitle].label
            snap(app, String(format: "%02d-%@", i + 4, sanitize(phase)))

            if app.otherElements[UIIdentifiers.Panel.dealFinished.rawValue].exists ||
               app.otherElements[UIIdentifiers.Panel.gameOver.rawValue].exists {
                break
            }

            if tapIfPresent(app, UIIdentifiers.bidButton(.pass)) { continue }
            if tapIfPresent(app, UIIdentifiers.whistButton(.pass)) { continue }
            if tryPlayHandCard(app) { continue }
            if tryDiscardTwo(app) { continue }
            if tapIfPresent(app, UIIdentifiers.buttonStartDeal) { continue }

            usleep(700_000)
        }

        snap(app, "99-final")
    }

    /// Plays a full 4-player match to pool target = 6 against three bots.
    /// Screenshots only on phase transitions + every deal-finished panel,
    /// so the artifact is one page per phase, not one per tick.
    func testHumanVsBotsFullMatchFourPlayersPoolSix() {
        let screenDir = URL(fileURLWithPath: "/Users/sol/projects/preferans/build/screens-match")
        try? FileManager.default.removeItem(at: screenDir)
        try? FileManager.default.createDirectory(at: screenDir, withIntermediateDirectories: true)
        var step = 0
        var lastSnapKey = ""
        func snap(_ app: XCUIApplication, _ name: String, force: Bool = false) {
            // De-dupe: only screenshot when the (phase, deal#, viewer)
            // tuple changes, otherwise we capture 60 identical frames during
            // bot-pacing pauses.
            // The lobby has no phase/viewer labels — query defensively so
            // the de-dupe key works in both lobby and in-game contexts.
            func labelIfExists(_ id: String) -> String {
                let el = app.staticTexts[id]
                return el.exists ? el.label : ""
            }
            let phase = labelIfExists(UIIdentifiers.phaseTitle)
            let viewer = labelIfExists(UIIdentifiers.viewerLabel)
            let trick = labelIfExists(UIIdentifiers.phaseMessage)
            let key = "\(phase)|\(viewer)|\(trick)"
            if !force && key == lastSnapKey { return }
            lastSnapKey = key
            let img = app.screenshot()
            let url = screenDir.appendingPathComponent(String(format: "match-%03d-%@.png", step, name))
            try? img.pngRepresentation.write(to: url)
            step += 1
        }
        func tapIfPresent(_ app: XCUIApplication, _ id: String) -> Bool {
            let b = app.buttons[id]
            guard b.exists, b.isHittable else { return false }
            b.tap()
            return true
        }
        /// Plays one card from the human hand. Tries each card identifier in
        /// turn; success is detected by the identifier disappearing from
        /// the hand row (engine accepted, hand resized).
        func playLegalHandCard(_ app: XCUIApplication) -> Bool {
            let predicate = NSPredicate(format: "identifier BEGINSWITH 'card.hand.You.'")
            let cards = app.buttons.matching(predicate)
            let count = cards.count
            for i in 0..<count {
                let card = cards.element(boundBy: i)
                guard card.exists, card.isHittable else { continue }
                let id = card.identifier
                card.tap()
                // Wait for the engine to either accept (id disappears) or
                // reject (id still there with the error banner visible).
                let gone = NSPredicate(format: "exists == false")
                let exp = XCTNSPredicateExpectation(predicate: gone, object: app.buttons[id])
                if XCTWaiter().wait(for: [exp], timeout: 0.25) == .completed {
                    return true
                }
            }
            return false
        }
        func tryDiscardTwo(_ app: XCUIApplication) -> Bool {
            let predicate = NSPredicate(format: "identifier BEGINSWITH 'card.discardSelect.'")
            let cards = app.buttons.matching(predicate)
            guard cards.count >= 2 else { return false }
            cards.element(boundBy: 0).tap()
            cards.element(boundBy: 1).tap()
            return tapIfPresent(app, UIIdentifiers.buttonDiscardSelected)
        }

        let app = XCUIApplication()
        // Pool target = 6, viewer follows actor, animations off so the
        // simulator burns less time on transitions.
        app.launchArguments += [
            UITestFlags.viewerFollowsActor,
            UITestFlags.disableAnimations,
            UITestFlags.poolTarget, "6",
        ]
        app.launch()
        snap(app, "01-lobby", force: true)

        // Switch lobby to 4 players, then start.
        let fourPlayers = app.buttons[UIIdentifiers.lobbyPlayerCountFour]
        XCTAssertTrue(fourPlayers.waitForExistence(timeout: 5))
        fourPlayers.tap()
        snap(app, "02-lobby-4p", force: true)
        let startTable = app.buttons[UIIdentifiers.lobbyStartLocalTable]
        XCTAssertTrue(startTable.waitForExistence(timeout: 3))
        startTable.tap()
        snap(app, "03-table-ready", force: true)

        // Drive the match: each loop iteration takes one human-side action
        // (or sleeps for bots), and snapshots phase transitions.
        let stepLimit = 800
        var dealStartCount = 0
        var sawGameOver = false
        for _ in 0..<stepLimit {
            snap(app, "tick")

            if app.otherElements[UIIdentifiers.Panel.gameOver.rawValue].exists ||
               app.staticTexts[UIIdentifiers.gameOverTitle].exists {
                sawGameOver = true
                snap(app, "match-over", force: true)
                break
            }

            // Between deals the engine surfaces a "Start next deal" button
            // inside the deal-finished sheet — different identifier from the
            // initial Start-deal button. Tap whichever is presented.
            if tapIfPresent(app, UIIdentifiers.buttonStartNextDealInSheet) {
                dealStartCount += 1
                snap(app, "deal-\(dealStartCount)-started", force: true)
                continue
            }
            if tapIfPresent(app, UIIdentifiers.buttonStartDeal) {
                dealStartCount += 1
                snap(app, "deal-\(dealStartCount)-started", force: true)
                continue
            }
            if tapIfPresent(app, UIIdentifiers.bidButton(.pass)) { continue }
            if tapIfPresent(app, UIIdentifiers.whistButton(.pass)) { continue }
            if playLegalHandCard(app) { continue }
            if tryDiscardTwo(app) { continue }

            // Bot turn — with bot delay = 0 (animations off) the next
            // human-actionable state lands fast; keep the idle short so
            // a stalled match fails loudly within ~30 s.
            usleep(80_000)
        }

        snap(app, "99-final", force: true)
        XCTAssertTrue(sawGameOver, "Match never reached gameOver in \(stepLimit) ticks (deals started: \(dealStartCount))")
    }
}
