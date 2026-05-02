import Foundation

/// Deterministic 64-bit pseudo-random number generator (SplitMix64).
///
/// Reference type so that copies share state — multiple `shuffled(using:)`
/// calls advance the same sequence, which makes scripted tests both
/// deterministic and easy to reason about across deals.
public final class SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    public func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z &>> 31)
    }
}

public extension Deck {
    /// Returns a shuffle of the standard 32-card deck driven by the given seed.
    /// Same seed always yields the same deck.
    static func shuffled(seed: UInt64) -> [Card] {
        var rng = SeededRandomNumberGenerator(seed: seed)
        return standard32.shuffled(using: &rng)
    }
}

/// Source of the next deck a deal should consume. Lets callers swap in
/// scripted or seeded deals for tests while keeping production behaviour
/// (system-random) by default.
public protocol DealSource: AnyObject {
    func nextDeck() -> [Card]
}

public final class RandomDealSource: DealSource {
    public init() {}
    public func nextDeck() -> [Card] {
        Deck.standard32.shuffled()
    }
}

public final class SeededDealSource: DealSource {
    private var rng: SeededRandomNumberGenerator

    public init(seed: UInt64) {
        self.rng = SeededRandomNumberGenerator(seed: seed)
    }

    public func nextDeck() -> [Card] {
        Deck.standard32.shuffled(using: &rng)
    }
}

public final class ScriptedDealSource: DealSource {
    private let decks: [[Card]]
    private var index = 0

    public init(decks: [[Card]]) {
        precondition(!decks.isEmpty, "ScriptedDealSource requires at least one deck")
        self.decks = decks
    }

    public func nextDeck() -> [Card] {
        defer { index += 1 }
        return decks[index % decks.count]
    }
}
