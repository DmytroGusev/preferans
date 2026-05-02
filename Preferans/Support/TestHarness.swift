import Foundation
import PreferansEngine

/// Test-time configuration sourced from process launch arguments.
///
/// Two layers:
/// - **Per-deal pinning** (`firstDealer`, `dealScenario`, `dealSeed`,
///   `viewerFollowsActor`): keeps the existing single-deal scenarios working
///   for the early UI smoke tests.
/// - **Whole-match scripting** (`matchScript`, `poolTarget`, `raspasy`,
///   `totus`, `players`, `firstDealer`): lets a UI test launch the app in
///   the same `MatchScript` the engine driver uses, so the UI test never
///   has to re-derive auctions, recipes, or play sequences.
///
/// When `matchScript` is set the harness resolves a canonical
/// ``MatchScriptFixtures`` value and replaces the lobby's defaults with the
/// script's `players`, `firstDealer`, `rules`, `match`, and a
/// ``ScriptedDealSource`` of recipe-built decks. Other launch arguments
/// override individual fields after the script is resolved.
public enum TestHarness {
    public typealias Flag = UITestFlags

    public static func disableAnimations(in arguments: [String]) -> Bool {
        arguments.contains(Flag.disableAnimations)
    }

    /// A fully resolved table configuration the lobby can use to build a
    /// `GameViewModel`. All fields are populated from launch arguments,
    /// canonical fixtures, or sensible production defaults.
    public struct Configuration {
        public let players: [PlayerID]
        public let firstDealer: PlayerID?
        public let rules: PreferansRules
        public let match: MatchSettings
        public let dealSource: DealSource
        /// When set, forces the lobby to use this viewer policy regardless
        /// of how many humans are at the table. UI tests use this to drive
        /// every seat through the screen ("follow the actor"). Production
        /// runs leave this nil and the lobby derives the policy from the
        /// human/bot mix.
        public let viewerPolicyOverride: ViewerPolicy?
    }

    public static func viewerFollowsActor(in arguments: [String]) -> Bool {
        arguments.contains(Flag.viewerFollowsActor)
    }

    public static func firstDealer(from arguments: [String]) -> PlayerID? {
        value(after: Flag.firstDealer, in: arguments).map { PlayerID($0) }
    }

    public static func dealSource(from arguments: [String]) -> DealSource {
        if let raw = value(after: Flag.dealScenario, in: arguments),
           let scenario = DealScenario(rawValue: raw) {
            return ScriptedDealSource(decks: scenario.decks)
        }
        if let raw = value(after: Flag.dealSeed, in: arguments),
           let seed = UInt64(raw) {
            return SeededDealSource(seed: seed)
        }
        return RandomDealSource()
    }

    /// Resolves the full table configuration. When `defaults` is provided
    /// (the lobby's own roster), it's used as the baseline and overridden
    /// only by launch-argument values that are present.
    public static func resolveConfiguration(
        from arguments: [String],
        defaults: Defaults
    ) -> Configuration {
        // 1. Start from a named match script when supplied — pulls in
        // players, firstDealer, rules, match, and the scripted deal source.
        var players = defaults.players
        var firstDealer = defaults.firstDealer
        var rules = PreferansRules.sochi
        var match = MatchSettings.unbounded
        var dealSource: DealSource = dealSource(from: arguments)

        if let scriptName = value(after: Flag.matchScript, in: arguments),
           let script = MatchScriptFixtures.script(named: scriptName) {
            players = script.players
            firstDealer = script.firstDealer
            rules = script.rules
            match = script.match
            dealSource = scriptedDealSource(for: script)
        }

        // 2. Per-field launch overrides (still in priority over any defaults).
        if let raw = value(after: Flag.players, in: arguments) {
            let parsed = raw.split(separator: ",").map { PlayerID(String($0)) }
            if !parsed.isEmpty { players = parsed }
        }
        if let raw = value(after: Flag.firstDealer, in: arguments) {
            firstDealer = PlayerID(raw)
        }
        if let raw = value(after: Flag.poolTarget, in: arguments), let target = Int(raw) {
            match = MatchSettings(poolTarget: target, raspasy: match.raspasy, totus: match.totus)
        }
        if let raw = value(after: Flag.raspasyPolicy, in: arguments),
           let parsed = parseRaspasyPolicy(raw) {
            match = MatchSettings(poolTarget: match.poolTarget, raspasy: parsed, totus: match.totus)
        }
        if let raw = value(after: Flag.totusPolicy, in: arguments),
           let parsed = parseTotusPolicy(raw) {
            match = MatchSettings(poolTarget: match.poolTarget, raspasy: match.raspasy, totus: parsed)
        }

        return Configuration(
            players: players,
            firstDealer: firstDealer,
            rules: rules,
            match: match,
            dealSource: dealSource,
            viewerPolicyOverride: viewerFollowsActor(in: arguments) ? .followsActor : nil
        )
    }

    public struct Defaults {
        public let players: [PlayerID]
        public let firstDealer: PlayerID?
        public init(players: [PlayerID], firstDealer: PlayerID? = nil) {
            self.players = players
            self.firstDealer = firstDealer
        }
    }

    /// Pre-builds the deck for every deal in the script using each deal's
    /// recipe and the engine's predicted active rotation, then wraps them
    /// in a ``ScriptedDealSource``. The engine consumes one deck per
    /// `startDeal` call so this stays in lock-step with the script.
    private static func scriptedDealSource(for script: MatchScript) -> DealSource {
        // Replay dealer rotation so the recipes get the same active set
        // the engine will derive on each startDeal.
        var dealer = script.firstDealer
        var decks: [[Card]] = []
        // Use a throwaway engine to compute rotations without applying
        // any actions — only `activePlayers(forDealer:)` is needed.
        guard let helper = try? PreferansEngine(
            players: script.players,
            rules: script.rules,
            match: script.match,
            firstDealer: script.firstDealer
        ) else {
            return ScriptedDealSource(decks: [Deck.standard32])
        }
        for deal in script.deals {
            let active = helper.activePlayers(forDealer: dealer)
            decks.append(deal.recipe.deck(for: active))
            dealer = nextDealer(after: dealer, in: script.players)
        }
        return ScriptedDealSource(decks: decks)
    }

    private static func nextDealer(after dealer: PlayerID, in players: [PlayerID]) -> PlayerID {
        guard let index = players.firstIndex(of: dealer) else { return players[0] }
        return players[(index + 1) % players.count]
    }

    private static func parseRaspasyPolicy(_ raw: String) -> RaspasyPolicy? {
        switch raw.lowercased() {
        case "singleshot", "single", "single_shot": return .singleShot
        default: return nil
        }
    }

    /// Encodings: `asTenTrickGame:<requireWhist>` or
    /// `dedicated:<requireWhist>:<bonusPool>` (booleans are `true`/`false`).
    private static func parseTotusPolicy(_ raw: String) -> TotusPolicy? {
        let parts = raw.split(separator: ":").map(String.init)
        guard !parts.isEmpty else { return nil }
        switch parts[0].lowercased() {
        case "astentrickgame":
            let req = parts.count > 1 && Bool(parts[1]) == true
            return .asTenTrickGame(requireWhist: req)
        case "dedicated", "dedicatedcontract":
            let req = parts.count > 1 && Bool(parts[1]) == true
            let bonus = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
            return .dedicatedContract(requireWhist: req, bonusPool: bonus)
        default:
            return nil
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }
}

/// Named, hand-curated decks used by tests to land the engine in a known
/// state in a single deal. Names describe the resulting game state, not the
/// deck contents, so callers don't have to think about card layouts.
///
/// All scenarios target a 3-player table with `firstDealer = "south"`, which
/// produces `activePlayers = [north, east, south]` so "north" is always the
/// first bidder. The decks are built by interleaving per-seat hands in the
/// same packet pattern the engine uses (see ``deck(north:east:south:talon:)``);
/// each scenario must therefore stay in lock-step with `PreferansEngine`'s
/// `dealHands` if that ever changes.
public enum DealScenario: String {
    /// Sorted standard deck — fully deterministic but otherwise unremarkable.
    /// Useful as a baseline for any test that just needs *some* fixed deal.
    case sortedDeck

    /// North gets ♠9–♠A plus ♣K, ♣A, ♦A, ♥A — a runaway 6♠ hand. East holds
    /// only ♠7, ♠8 in trumps, south holds none. Use to drive talon take,
    /// 2-card discard, contract declaration, and whist responses.
    case northBidsSpadesSix

    /// North gets the 10 lowest cards in the deck — no trick-takers — perfect
    /// for a misère bid. East and south get the top half so they can punish
    /// any non-misère contract.
    case northBidsMisere

    public var decks: [[Card]] {
        switch self {
        case .sortedDeck:
            return [Deck.standard32]
        case .northBidsSpadesSix:
            return [Self.northSpadesSixDeck]
        case .northBidsMisere:
            return [Self.northMisereDeck]
        }
    }

    /// Constructs a deck whose dealing-by-position produces the listed hands.
    /// Mirrors the 5-packet structure of `PreferansEngine.dealHands`: in each
    /// packet, north/east/south each pick up 2 cards in turn, and the talon
    /// takes 2 cards after the first packet. Crashes loudly if the inputs
    /// aren't a valid 32-card permutation.
    private static func deck(north: [Card], east: [Card], south: [Card], talon: [Card]) -> [Card] {
        precondition(north.count == 10 && east.count == 10 && south.count == 10 && talon.count == 2,
                     "scenario must allocate 10/10/10/2 cards")
        let seats = [north, east, south]
        var seatCursors = [0, 0, 0]
        var talonCursor = 0
        var deck: [Card] = []
        for packet in 0..<5 {
            for seat in seats.indices {
                deck.append(seats[seat][seatCursors[seat]])
                deck.append(seats[seat][seatCursors[seat] + 1])
                seatCursors[seat] += 2
            }
            if packet == 0 {
                deck.append(talon[talonCursor])
                deck.append(talon[talonCursor + 1])
                talonCursor += 2
            }
        }
        precondition(Set(deck) == Set(Deck.standard32),
                     "scenario deck must be a permutation of the standard 32-card deck")
        return deck
    }

    private static let northSpadesSixDeck: [Card] = deck(
        north: [
            Card(.spades, .ace), Card(.spades, .king),
            Card(.spades, .queen), Card(.spades, .jack),
            Card(.spades, .ten), Card(.spades, .nine),
            Card(.clubs, .ace), Card(.clubs, .king),
            Card(.diamonds, .ace), Card(.hearts, .ace)
        ],
        east: [
            Card(.spades, .eight), Card(.spades, .seven),
            Card(.clubs, .queen), Card(.clubs, .jack),
            Card(.hearts, .king), Card(.hearts, .queen),
            Card(.diamonds, .king), Card(.diamonds, .queen),
            Card(.hearts, .seven), Card(.diamonds, .seven)
        ],
        south: [
            Card(.clubs, .ten), Card(.clubs, .nine),
            Card(.clubs, .eight), Card(.clubs, .seven),
            Card(.hearts, .jack), Card(.hearts, .ten),
            Card(.hearts, .nine), Card(.hearts, .eight),
            Card(.diamonds, .ten), Card(.diamonds, .eight)
        ],
        talon: [Card(.diamonds, .jack), Card(.diamonds, .nine)]
    )

    private static let northMisereDeck: [Card] = deck(
        north: [
            Card(.spades, .seven), Card(.spades, .eight),
            Card(.clubs, .seven), Card(.clubs, .eight),
            Card(.diamonds, .seven), Card(.diamonds, .eight),
            Card(.hearts, .seven), Card(.hearts, .eight),
            Card(.hearts, .nine), Card(.diamonds, .nine)
        ],
        east: [
            Card(.spades, .ace), Card(.spades, .king),
            Card(.clubs, .ace), Card(.clubs, .king),
            Card(.diamonds, .ace), Card(.diamonds, .king),
            Card(.hearts, .ace), Card(.hearts, .king),
            Card(.hearts, .queen), Card(.hearts, .jack)
        ],
        south: [
            Card(.spades, .queen), Card(.spades, .jack),
            Card(.spades, .ten), Card(.spades, .nine),
            Card(.clubs, .queen), Card(.clubs, .jack),
            Card(.clubs, .ten), Card(.clubs, .nine),
            Card(.diamonds, .queen), Card(.diamonds, .jack)
        ],
        talon: [Card(.hearts, .ten), Card(.diamonds, .ten)]
    )
}
