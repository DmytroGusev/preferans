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

    init(app: XCUIApplication, defaultTimeout: TimeInterval = 5.0) {
        self.app = app
        self.defaultTimeout = defaultTimeout
    }

    // MARK: - Lobby

    func startLocalTable() {
        let button = app.buttons[UIIdentifiers.lobbyStartLocalTable]
        XCTAssertTrue(button.waitForExistence(timeout: defaultTimeout),
                      "Lobby's Start Local Table button never appeared.")
        button.tap()
    }

    func selectPlayerCount(_ count: Int) {
        let id = count == 4 ? UIIdentifiers.lobbyPlayerCountFour : UIIdentifiers.lobbyPlayerCountThree
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: defaultTimeout),
                      "Lobby's player-count(\(count)) button never appeared.")
        button.tap()
    }

    func setPlayerName(at index: Int, to name: String) {
        let field = app.textFields[UIIdentifiers.lobbyPlayerNameField(index: index)]
        XCTAssertTrue(field.waitForExistence(timeout: defaultTimeout),
                      "Lobby's player-name field [\(index)] never appeared.")
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
            tapStaticText(id: UIIdentifiers.card(card, in: .discardSelect), descriptor: "discard pick \(card)")
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
        tapStaticText(id: UIIdentifiers.card(card, in: .hand(seat: player)),
                      descriptor: "play \(card) from \(player)'s hand")
    }

    func startNextDeal() {
        tapButton(id: UIIdentifiers.buttonStartDeal, descriptor: "Start Deal")
    }

    // MARK: - Reading state

    /// Current phase title (e.g. "Bidding", "Talon exchange", "Game over").
    func phaseTitle() -> String {
        let element = app.staticTexts[UIIdentifiers.phaseTitle]
        XCTAssertTrue(element.waitForExistence(timeout: defaultTimeout),
                      "Phase title never appeared.")
        return element.label
    }

    /// Current phase message (the secondary line under the title).
    func phaseMessage() -> String {
        let element = app.staticTexts[UIIdentifiers.phaseMessage]
        XCTAssertTrue(element.waitForExistence(timeout: defaultTimeout))
        return element.label
    }

    /// Player the screen is currently following (parsed from "You are: X").
    func currentViewer() -> PlayerID? {
        let element = app.staticTexts[UIIdentifiers.viewerLabel]
        guard element.waitForExistence(timeout: defaultTimeout) else { return nil }
        let prefix = "You are: "
        let label = element.label
        guard label.hasPrefix(prefix) else { return nil }
        return PlayerID(String(label.dropFirst(prefix.count)))
    }

    /// Pool value for a player (parsed from the score cell).
    func pool(of player: PlayerID) -> Int {
        readInt(id: UIIdentifiers.scorePool(player), descriptor: "pool for \(player)")
    }

    /// Mountain value for a player.
    func mountain(of player: PlayerID) -> Int {
        readInt(id: UIIdentifiers.scoreMountain(player), descriptor: "mountain for \(player)")
    }

    /// Trick count displayed on a player's seat.
    func trickCount(of player: PlayerID) -> Int {
        let element = app.staticTexts[UIIdentifiers.seatTrickCount(player)]
        guard element.waitForExistence(timeout: defaultTimeout) else { return 0 }
        // Label form: "Tricks: 3"
        let raw = element.label.replacingOccurrences(of: "Tricks: ", with: "")
        return Int(raw) ?? 0
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
        // Label form: "Winner: X"
        let prefix = "Winner: "
        let label = element.label
        guard label.hasPrefix(prefix) else { return nil }
        return PlayerID(String(label.dropFirst(prefix.count)))
    }

    /// Number of deals played before the match closed (game-over panel only).
    func gameOverDealsPlayed() -> Int? {
        let element = app.staticTexts[UIIdentifiers.gameOverDealsPlayed]
        guard element.exists else { return nil }
        // Label form: "Deals played: N"
        let prefix = "Deals played: "
        let label = element.label
        guard label.hasPrefix(prefix) else { return nil }
        return Int(String(label.dropFirst(prefix.count)))
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

    // MARK: - Synchronization

    /// Blocks until the phase title equals `expected`. Distinct from
    /// `waitForElement` because the phase title element always exists — it's
    /// the *label* that changes between phases.
    func waitForPhase(_ expected: String, timeout: TimeInterval? = nil) {
        let element = app.staticTexts[UIIdentifiers.phaseTitle]
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
        XCTAssertTrue(element.waitForExistence(timeout: timeout ?? defaultTimeout),
                      "Element \"\(identifier)\" never appeared.")
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
        XCTAssertTrue(button.waitForExistence(timeout: defaultTimeout),
                      "Button for \(descriptor) (id: \(id)) never appeared.")
        button.tap()
    }

    /// CardView is rendered as a Text + .onTapGesture, so it appears as a
    /// staticText (not a button) in the accessibility tree.
    private func tapStaticText(id: String, descriptor: String) {
        let element = app.staticTexts[id]
        XCTAssertTrue(element.waitForExistence(timeout: defaultTimeout),
                      "Tappable text for \(descriptor) (id: \(id)) never appeared.")
        element.tap()
    }

    private func readInt(id: String, descriptor: String) -> Int {
        let element = app.staticTexts[id]
        XCTAssertTrue(element.waitForExistence(timeout: defaultTimeout),
                      "Score cell \(descriptor) (id: \(id)) never appeared.")
        return Int(element.label) ?? 0
    }
}

// MARK: - Launch-argument builder

extension XCUIApplication {
    /// Launch-argument flag strings duplicated here (must stay in sync with
    /// `Preferans/Support/TestHarness.swift`). The app target's TestHarness
    /// isn't visible to the UI test target, so the robot owns the strings.
    enum Flag {
        static let viewerFollowsActor = "-uiTestViewerFollowsActor"
        static let firstDealer        = "-uiTestFirstDealer"
        static let dealSeed           = "-uiTestDealSeed"
        static let dealScenario       = "-uiTestDealScenario"
        static let matchScript        = "-uiTestMatchScript"
        static let players            = "-uiTestPlayers"
        static let poolTarget         = "-uiTestPoolTarget"
        static let raspasyPolicy      = "-uiTestRaspasyPolicy"
        static let totusPolicy        = "-uiTestTotusPolicy"
    }

    /// Convenience: appends the harness flags needed to load a canonical
    /// match script and have the rotating viewer follow the actor. Tests
    /// add domain-specific overrides on top of this.
    func configureForMatchScript(_ name: String, extra: [String] = []) {
        launchArguments += [
            Flag.viewerFollowsActor,
            Flag.matchScript, name
        ]
        launchArguments += extra
    }
}
