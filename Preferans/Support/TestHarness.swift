import Foundation
import PreferansEngine

/// Test-time configuration sourced from process launch arguments.
/// The harness is consulted by ``LobbyView`` so UI tests can pin the
/// deal — fixed dealer + reproducible deck — without changing default
/// (production) behaviour.
///
/// When both ``Flag/dealScenario`` and ``Flag/dealSeed`` are passed, the
/// scenario takes precedence and the seed is ignored.
public enum TestHarness {
    public enum Flag {
        public static let viewerFollowsActor = "-uiTestViewerFollowsActor"
        public static let firstDealer = "-uiTestFirstDealer"
        public static let dealSeed = "-uiTestDealSeed"
        public static let dealScenario = "-uiTestDealScenario"
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
