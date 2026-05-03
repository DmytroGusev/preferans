import XCTest
import PreferansEngine

/// Thin wrapper over `XCUIApplication` that exposes the SwiftUI surface in
/// terms of engine values: `BidCall`, `GameContract`, `WhistCall`, `Card`,
/// `PlayerID`. The robot is the **only** test-target code that knows
/// accessibility identifier strings — every other UI-test layer (the driver,
/// the scenario tests) talks to the robot in domain types.
///
/// The robot is the dual of `PreferansEngine.apply(_:)`: each domain action
/// has one robot method, each engine query has one robot read. Robot calls
/// are synchronous and synchronise on the next expected UI element so the
/// caller never needs `sleep` or polling.
@MainActor
final class MatchUIRobot {
    let app: XCUIApplication

    /// Default wait for any element existence check. SwiftUI re-renders
    /// take ~100ms in steady state but bidding/play transitions can hit
    /// 500ms on cold-start frames. 5 seconds keeps the test responsive
    /// without flaking on a busy CI runner.
    let defaultTimeout: TimeInterval
    private let optionalReadTimeout: TimeInterval = 0.25

    init(app: XCUIApplication, defaultTimeout: TimeInterval = 5.0) {
        self.app = app
        self.defaultTimeout = defaultTimeout
    }

    // MARK: - Lobby

    func startLocalTable() {
        let button = app.buttons[UIIdentifiers.lobbyStartLocalTable]
        assertExists(button, "Lobby's Start Local Table button never appeared.")
        button.tap()
    }

    func selectPlayerCount(_ count: Int) {
        let id = count == 4 ? UIIdentifiers.lobbyPlayerCountFour : UIIdentifiers.lobbyPlayerCountThree
        let button = app.buttons[id]
        assertExists(button, "Lobby's player-count(\(count)) button never appeared.")
        button.tap()
    }

    func setPlayerName(at index: Int, to name: String) {
        let field = app.textFields[UIIdentifiers.lobbyPlayerNameField(index: index)]
        assertExists(field, "Lobby's player-name field [\(index)] never appeared.")
        field.tap()
        field.press(forDuration: 1.2)
        // Select-all then type — most reliable cross-iOS-version replacement.
        if let selectAll = app.menuItems["Select All"].firstMatch as XCUIElement?, selectAll.exists {
            selectAll.tap()
        }
        field.typeText(name)
    }

    // MARK: - In-game actions

    func bid(_ call: BidCall) {
        tapButton(id: UIIdentifiers.bidButton(call), descriptor: "bid \(call)")
    }

    func discard(_ cards: [Card]) {
        precondition(cards.count == 2, "Discard must contain exactly two cards; got \(cards.count).")
        for card in cards {
            tapCard(id: UIIdentifiers.card(card, in: .discardSelect), descriptor: "discard pick \(card)")
        }
        tapButton(id: UIIdentifiers.buttonDiscardSelected, descriptor: "Discard selected")
    }

    func declareContract(_ contract: GameContract) {
        tapButton(id: UIIdentifiers.contractButton(contract), descriptor: "declare \(contract)")
    }

    func declareTotusStrain(_ strain: Strain) {
        // Totus declarations reuse the contract button identifier with a
        // 10-trick contract in the picked strain.
        tapButton(id: UIIdentifiers.contractButton(GameContract(10, strain)),
                  descriptor: "declare totus strain \(strain)")
    }

    func whist(_ call: WhistCall) {
        tapButton(id: UIIdentifiers.whistButton(call), descriptor: "whist \(call)")
    }

    func defenderMode(_ mode: DefenderPlayMode) {
        tapButton(id: UIIdentifiers.defenderModeButton(mode), descriptor: "defender mode \(mode)")
    }

    func play(_ card: Card, by player: PlayerID) {
        tapCard(id: UIIdentifiers.card(card, in: .hand(seat: player)),
                      descriptor: "play \(card) from \(player)'s hand")
    }

    func startNextDeal() {
        tapButton(id: UIIdentifiers.buttonStartDeal, descriptor: "Deal")
    }

    @discardableResult
    func tapIfPresent(_ identifier: String) -> Bool {
        let button = app.buttons[identifier]
        guard button.exists, button.isHittable else { return false }
        button.tap()
        return true
    }

    @discardableResult
    func discardFirstTwoVisibleCards() -> Bool {
        let predicate = NSPredicate(format: "identifier BEGINSWITH 'card.discardSelect.'")
        let cards = app.buttons.matching(predicate)
        guard cards.count >= 2 else { return false }
        cards.element(boundBy: 0).tap()
        cards.element(boundBy: 1).tap()
        return tapIfPresent(UIIdentifiers.buttonDiscardSelected)
    }

    /// Tries visible hand cards in order and returns after the first accepted
    /// play. Success is detected by the tapped identifier leaving the hand row.
    @discardableResult
    func playFirstAcceptedHandCard(for seat: PlayerID, acceptanceTimeout: TimeInterval = 0.25) -> Bool {
        let prefix = "card.hand.\(seat.rawValue)."
        let playable = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND value == %@", prefix, "Playable")
        )
        if playable.count > 0 {
            let card = playable.element(boundBy: 0)
            guard card.exists, card.isHittable else { return false }
            let id = card.identifier
            card.tap()
            let gone = NSPredicate(format: "exists == false")
            let exp = XCTNSPredicateExpectation(predicate: gone, object: app.buttons[id])
            return XCTWaiter().wait(for: [exp], timeout: acceptanceTimeout) == .completed
        }

        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", prefix)
        let cards = app.buttons.matching(predicate)
        let count = cards.count
        guard count > 0 else { return false }
        for index in 0..<count {
            let card = cards.element(boundBy: index)
            guard card.exists, card.isHittable else { continue }
            let id = card.identifier
            card.tap()

            let gone = NSPredicate(format: "exists == false")
            let exp = XCTNSPredicateExpectation(predicate: gone, object: app.buttons[id])
            if XCTWaiter().wait(for: [exp], timeout: acceptanceTimeout) == .completed {
                return true
            }
        }
        return false
    }

    // MARK: - Reading state

    /// Current phase title (e.g. "Bidding", "Prikup exchange", "Game over").
    func phaseTitle() -> String {
        let element = app.staticTexts[UIIdentifiers.phaseTitle]
        assertExists(element, "Phase title never appeared.")
        return element.label
    }

    /// Current phase message (the secondary line under the title).
    func phaseMessage() -> String {
        let element = app.staticTexts[UIIdentifiers.phaseMessage]
        assertExists(element, "Phase message never appeared.")
        return element.label
    }

    /// Player the screen is currently following (parsed from "Viewing as X").
    func currentViewer() -> PlayerID? {
        let element = app.staticTexts[UIIdentifiers.viewerLabel]
        guard exists(element, timeout: optionalReadTimeout) else { return nil }
        let prefix = AccessibilityStrings.viewerLabelPrefix
        let label = element.label
        guard label.hasPrefix(prefix) else { return nil }
        return PlayerID(String(label.dropFirst(prefix.count)))
    }

    /// Pool value for a player (parsed from the score cell).
    func pool(of player: PlayerID) -> Int {
        scoreSnapshot(for: [player])[player]?.pool ?? 0
    }

    /// Mountain value for a player.
    func mountain(of player: PlayerID) -> Int {
        scoreSnapshot(for: [player])[player]?.mountain ?? 0
    }

    /// Pool/mountain values for the given players. On compact layouts the
    /// scoresheet lives in a toolbar sheet, so read all requested cells in
    /// one visit instead of opening the sheet per assertion.
    func scoreSnapshot(for players: [PlayerID]) -> [PlayerID: (pool: Int, mountain: Int)] {
        withScoreSheet {
            players.reduce(into: [:]) { snapshot, player in
                snapshot[player] = (
                    pool: readInt(id: UIIdentifiers.scorePool(player), descriptor: "pool for \(player)"),
                    mountain: readInt(id: UIIdentifiers.scoreMountain(player), descriptor: "mountain for \(player)")
                )
            }
        }
    }

    /// Trick count displayed on a player's seat.
    func trickCount(of player: PlayerID) -> Int {
        let element = app.staticTexts[UIIdentifiers.seatTrickCount(player)]
        guard exists(element, timeout: optionalReadTimeout) else { return 0 }
        return firstInteger(in: element.label) ?? 0
    }

    /// Encoded result of the most recent finished deal (e.g. `game.east.6S.south+west`).
    /// `nil` when the deal-finished panel isn't visible.
    func dealResultKind() -> String? {
        let element = app.staticTexts[UIIdentifiers.dealResultKind]
        guard element.exists else { return nil }
        return element.label
    }

    /// Match-summary winner shown on the game-over panel.
    func gameOverWinner() -> PlayerID? {
        let element = app.staticTexts[UIIdentifiers.gameOverWinner]
        guard element.exists else { return nil }
        let label = element.label
        let prefix = AccessibilityStrings.gameOverWinnerPrefix
        if label.hasPrefix(prefix) {
            return PlayerID(String(label.dropFirst(prefix.count)))
        }
        if let name = label.components(separatedBy: " takes the pulka").first, name != label {
            return PlayerID(name)
        }
        return nil
    }

    /// Number of deals played before the match closed (game-over panel only).
    func gameOverDealsPlayed() -> Int? {
        let element = app.staticTexts[UIIdentifiers.gameOverDealsPlayed]
        guard element.exists else { return nil }
        let prefix = AccessibilityStrings.completedDealsPrefix
        if element.label.hasPrefix(prefix) {
            return Int(String(element.label.dropFirst(prefix.count)))
        }
        return firstInteger(in: element.label)
    }

    /// True when the engine has reached the gameOver terminal state.
    func isMatchOver() -> Bool {
        app.otherElements[UIIdentifiers.Panel.gameOver.rawValue].exists
            || app.staticTexts[UIIdentifiers.gameOverTitle].exists
    }

    /// Last error surfaced by the engine, if any (banner at the bottom of
    /// the screen). `nil` when the banner isn't visible.
    func errorBanner() -> String? {
        let element = app.staticTexts[UIIdentifiers.errorBanner]
        guard element.exists else { return nil }
        return element.label
    }

    func labelIfExists(_ identifier: String) -> String {
        let element = app.staticTexts[identifier]
        return element.exists ? element.label : ""
    }

    func screenshotDeduplicationKey() -> String {
        [
            labelIfExists(UIIdentifiers.phaseTitle),
            labelIfExists(UIIdentifiers.viewerLabel),
            labelIfExists(UIIdentifiers.phaseMessage)
        ].joined(separator: "|")
    }

    // MARK: - Synchronization

    /// Blocks until the phase title equals `expected`. Distinct from
    /// `waitForElement` because the phase title element always exists — it's
    /// the *label* that changes between phases.
    func waitForPhase(_ expected: String, timeout: TimeInterval? = nil) {
        let element = app.staticTexts[UIIdentifiers.phaseTitle]
        if element.exists, element.label == expected { return }
        let predicate = NSPredicate(format: "label == %@", expected)
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let waitTime = timeout ?? defaultTimeout
        let result = XCTWaiter().wait(for: [exp], timeout: waitTime)
        XCTAssertEqual(result, .completed,
                       "Phase did not transition to \"\(expected)\" within \(waitTime)s. Current: \"\(element.label)\".")
    }

    /// Blocks until any element with the given identifier exists. Useful for
    /// waiting on panels that appear/disappear (e.g. discard panel after
    /// auction win).
    func waitForElement(_ identifier: String, timeout: TimeInterval? = nil) {
        let element = app.descendants(matching: .any).matching(identifier: identifier).element
        assertExists(element, timeout: timeout, "Element \"\(identifier)\" never appeared.")
    }

    /// Blocks until the integer value at a score cell crosses `target` from
    /// below. Useful for asserting "east's pool reached at least 10".
    func waitForPoolAtLeast(_ target: Int, of player: PlayerID, timeout: TimeInterval? = nil) {
        let element = app.staticTexts[UIIdentifiers.scorePool(player)]
        let predicate = NSPredicate { _, _ in
            Int(element.label) ?? 0 >= target
        }
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        let waitTime = timeout ?? defaultTimeout
        let result = XCTWaiter().wait(for: [exp], timeout: waitTime)
        XCTAssertEqual(result, .completed,
                       "Pool for \(player) never reached \(target) (final: \(element.label)).")
    }

    // MARK: - Internal helpers

    private func tapButton(id: String, descriptor: String) {
        let button = app.buttons[id]
        assertExists(button, "Button for \(descriptor) (id: \(id)) never appeared.")
        XCTAssertTrue(button.isEnabled,
                      "Button for \(descriptor) (id: \(id)) appeared but was disabled.")
        button.tap()
    }

    /// `CardView` always sets `.accessibilityAddTraits(.isButton)`, so cards
    /// surface as buttons in the XCUI hierarchy. The hand is an overlapping
    /// fan, so tap the exposed leading sliver instead of the card center.
    private func tapCard(id: String, descriptor: String) {
        let button = app.buttons[id]
        assertExists(button, "Card button for \(descriptor) (id: \(id)) never appeared.")
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
    }

    private func readInt(id: String, descriptor: String) -> Int {
        let element = app.staticTexts[id]
        assertExists(element, "Score cell \(descriptor) (id: \(id)) never appeared.")
        return Int(element.label) ?? 0
    }

    private func firstInteger(in text: String) -> Int? {
        var digits = ""
        for character in text {
            if character.isNumber {
                digits.append(character)
            } else if !digits.isEmpty {
                break
            }
        }
        return Int(digits)
    }

    private func withScoreSheet<T>(_ body: () -> T) -> T {
        let scorePanel = app.otherElements[UIIdentifiers.Panel.score.rawValue]
        guard !scorePanel.exists else { return body() }

        // The Scoresheet entry now lives inside the overflow menu in the
        // header strip. Open the menu first; the menu items only become
        // tappable once it's expanded.
        openOverflowMenu()
        let scoreButton = app.buttons[UIIdentifiers.buttonScoreSheet]
        assertExists(scoreButton, "Scoresheet button never appeared.")
        scoreButton.tap()
        waitForElement(UIIdentifiers.Panel.score.rawValue)
        let value = body()
        let doneButton = app.buttons[UIIdentifiers.buttonDismissSheet]
        if exists(doneButton, timeout: optionalReadTimeout) {
            doneButton.tap()
        }
        return value
    }

    /// Open the in-game overflow menu (`…`). The Scoresheet, Settings, and
    /// View-as entries all live inside it, so reads of any of those are
    /// gated on the menu being expanded first.
    private func openOverflowMenu() {
        let menuButton = app.buttons[UIIdentifiers.overflowMenu]
        assertExists(menuButton, "Overflow menu never appeared.")
        menuButton.tap()
    }

    @discardableResult
    private func assertExists(
        _ element: XCUIElement,
        timeout: TimeInterval? = nil,
        _ message: @autoclosure () -> String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let found = exists(element, timeout: timeout)
        XCTAssertTrue(found, "\(message())\(phaseContextSuffix())", file: file, line: line)
        return found
    }

    private func exists(_ element: XCUIElement, timeout: TimeInterval? = nil) -> Bool {
        element.exists || element.waitForExistence(timeout: timeout ?? defaultTimeout)
    }

    private func phaseContextSuffix() -> String {
        let phase = app.staticTexts[UIIdentifiers.phaseTitle]
        let viewer = app.staticTexts[UIIdentifiers.viewerLabel]
        let error = app.staticTexts[UIIdentifiers.errorBanner]
        var context: [String] = []
        if phase.exists { context.append("phase: \(phase.label)") }
        if viewer.exists { context.append("viewer: \(viewer.label)") }
        if error.exists { context.append("error: \(error.label)") }
        return context.isEmpty ? "" : " [\(context.joined(separator: ", "))]"
    }
}

@MainActor
final class MatchScreenshotRecorder {
    private let testCase: XCTestCase
    private let app: XCUIApplication
    private let outputDirectory: URL?
    private let filePrefix: String
    private var step = 0
    private var lastKey = ""

    init(
        testCase: XCTestCase,
        app: XCUIApplication,
        outputDirectory: URL? = nil,
        filePrefix: String = "screen"
    ) {
        self.testCase = testCase
        self.app = app
        self.outputDirectory = outputDirectory
        self.filePrefix = filePrefix
        if let outputDirectory {
            try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        }
    }

    func capture(name: String, key: String? = nil, force: Bool = false, attach: Bool = true) {
        if let key {
            guard force || key != lastKey else { return }
            lastKey = key
        }

        let screenshot = app.screenshot()
        if let outputDirectory {
            let url = outputDirectory.appendingPathComponent(String(format: "%@-%03d-%@.png", filePrefix, step, name))
            try? screenshot.pngRepresentation.write(to: url)
        }
        step += 1

        if attach {
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = name
            attachment.lifetime = .keepAlways
            testCase.add(attachment)
        }
    }
}

// MARK: - Launch-argument builder

extension XCUIApplication {
    /// Convenience: appends the harness flags needed to load a canonical
    /// match script and have the rotating viewer follow the actor. Animations
    /// are disabled by default so taps land on settled frames; pass
    /// `disableAnimations: false` for screenshot tests that need motion.
    func configureForMatchScript(_ name: String, extra: [String] = [], disableAnimations: Bool = true) {
        launchArguments += [
            UITestFlags.viewerFollowsActor,
            UITestFlags.matchScript, name
        ]
        if disableAnimations {
            launchArguments += [UITestFlags.disableAnimations]
        }
        launchArguments += extra
    }

    /// Apply the disable-animations harness flag without any match-script
    /// configuration. Use for raw lobby/bidding tests that build their own
    /// launch-argument list but still want the animation-free fast path.
    func disableUITestAnimations() {
        launchArguments += [UITestFlags.disableAnimations]
    }
}
