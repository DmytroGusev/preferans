import Foundation

/// Heuristic hand evaluation used by the rule-based parts of the bot
/// (bidding, whist/pass, discard, contract declaration). Returns expected
/// trick counts as fractional estimates so callers can compare directly
/// against contract trick targets.
public enum HandEvaluator {
    public typealias SuitGrouping = [Suit: [Card]]

    public static func groupBySuit(_ hand: [Card]) -> SuitGrouping {
        Dictionary(grouping: hand, by: \.suit)
    }

    public static func expectedDeclarerTricks(hand: [Card], trump: Suit?) -> Double {
        expectedDeclarerTricks(grouped: groupBySuit(hand), trump: trump)
    }

    public static func expectedDeclarerTricks(grouped: SuitGrouping, trump: Suit?) -> Double {
        var tricks = 0.0
        for suit in Suit.allCases {
            let cards = (grouped[suit] ?? []).sorted(by: >)
            tricks += suitTricks(cards: cards, isTrump: trump == suit, trumpSuit: trump)
        }
        return tricks
    }

    /// Expected tricks the hand is *forced* to take in misère. Lower is
    /// better. < 0.5 is a strong misère hand; > 1.5 is risky.
    public static func expectedMisereTricks(hand: [Card]) -> Double {
        expectedMisereTricks(grouped: groupBySuit(hand))
    }

    public static func expectedMisereTricks(grouped: SuitGrouping) -> Double {
        var forced = 0.0
        for suit in Suit.allCases {
            let cards = (grouped[suit] ?? []).sorted(by: >)
            forced += misereSuitTricks(cards: cards)
        }
        return forced
    }

    public static func expectedAllPassTricks(hand: [Card]) -> Double {
        expectedAllPassTricks(grouped: groupBySuit(hand))
    }

    public static func expectedAllPassTricks(grouped: SuitGrouping) -> Double {
        var forced = 0.0
        for suit in Suit.allCases {
            let cards = (grouped[suit] ?? []).sorted(by: >)
            forced += allPassSuitTricks(cards: cards)
        }
        return forced
    }

    public static func expectedDefenderTricks(hand: [Card], trump: Suit?) -> Double {
        // Defensive tricks are dominated by side-suit aces and trump
        // honors; length tricks rarely cash from defense in a 32-card deck.
        let grouped = groupBySuit(hand)
        var tricks = 0.0
        for suit in Suit.allCases {
            let cards = (grouped[suit] ?? []).sorted(by: >)
            tricks += defenderSuitTricks(cards: cards, isTrump: trump == suit)
        }
        return tricks
    }

    private static func suitTricks(cards: [Card], isTrump: Bool, trumpSuit: Suit?) -> Double {
        guard !cards.isEmpty else { return 0 }
        let length = cards.count
        let ranks = cards.map(\.rank)
        var t = 0.0

        // Honor tricks: A=1, AK=2, AKQ=3, KQ=1, K guarded=0.5, etc.
        // 32-card deck means K with 1 cover is well-protected; Q needs
        // 2 covers (J or length).
        let hasA = ranks.contains(.ace)
        let hasK = ranks.contains(.king)
        let hasQ = ranks.contains(.queen)
        let hasJ = ranks.contains(.jack)

        if hasA { t += 1.0 }
        if hasA && hasK { t += 1.0 }
        else if hasK && length >= 2 { t += 0.5 }
        if hasA && hasK && hasQ { t += 1.0 }
        else if hasK && hasQ { t += 0.5 }
        else if hasQ && length >= 3 { t += 0.25 }
        if hasJ && length >= 4 && hasQ { t += 0.25 }

        if isTrump {
            // Trump length: each trump beyond 3 ≈ half a trick; ruffing
            // power compounds at length 5+.
            if length >= 4 { t += Double(length - 3) * 0.5 }
            if length >= 5 { t += 0.25 }
        } else if trumpSuit == nil {
            // No-trump: long side suits cash once high cards flush, but
            // only when topped by an ace.
            if length >= 4 && hasA { t += Double(length - 3) * 0.4 }
        }

        return t
    }

    private static func misereSuitTricks(cards: [Card]) -> Double {
        guard !cards.isEmpty else { return 0 }
        // Walk the suit ascending; every gap above a contiguous-from-7
        // run risks a forced trick. A hand without a 7 in the suit also
        // risks one because opponents may underlead it.
        let ascending = cards.map(\.rank.rawValue).sorted()
        guard let lowest = ascending.first else { return 0 }
        if lowest > 7 { return 1.0 }
        var forced = 0.0
        var expectedNext = 7
        for r in ascending {
            if r == expectedNext {
                expectedNext += 1
                continue
            }
            forced += 0.5
            expectedNext = r + 1
        }
        return forced
    }

    private static func allPassSuitTricks(cards: [Card]) -> Double {
        guard !cards.isEmpty else { return 0 }
        let ranks = Set(cards.map(\.rank))
        var forced = 0.0
        if ranks.contains(.ace) { forced += 1.0 }
        if ranks.contains(.king) {
            forced += ranks.contains(.ace) ? 0.4 : 0.5
        }
        if ranks.contains(.queen), cards.count <= 2 {
            forced += 0.3
        }
        // Long suits (5+) tend to take a length trick after opponents
        // discard out.
        if cards.count >= 5 { forced += 0.4 }
        return forced
    }

    private static func defenderSuitTricks(cards: [Card], isTrump: Bool) -> Double {
        guard !cards.isEmpty else { return 0 }
        let ranks = Set(cards.map(\.rank))
        var t = 0.0
        if ranks.contains(.ace) { t += 1.0 }
        if isTrump {
            if ranks.contains(.king) { t += 0.6 }
            if ranks.contains(.queen) { t += 0.3 }
            if cards.count >= 4 { t += 0.4 } // ruff/over-ruff potential
        } else {
            if ranks.contains(.king), cards.count >= 2 { t += 0.4 }
        }
        return max(0, t)
    }
}
