import Foundation
import GameplayKit

/// Deterministic 64-bit pseudo-random number generator backed by
/// `GameplayKit`'s Mersenne Twister source — the canonical Apple
/// platform seeded RNG, with a longer period and better statistical
/// distribution than a hand-rolled SplitMix64.
///
/// `GKMersenneTwisterRandomSource.nextInt()` returns 32 random bits
/// per call (uniform across `Int32`'s full range), so each `next()`
/// pulls two and concatenates to produce 64 bits the
/// `RandomNumberGenerator` protocol asks for.
///
/// Reference type so that copies share state — multiple
/// `shuffled(using:)` calls advance the same sequence, which makes
/// scripted tests both deterministic and easy to reason about across
/// deals.
public final class SeededRandomNumberGenerator: RandomNumberGenerator {
    private let source: GKMersenneTwisterRandomSource

    public init(seed: UInt64) {
        // GKMersenneTwisterRandomSource accepts any UInt64 including 0;
        // keep the legacy "0 → fixed sentinel" behavior so tests that
        // pass seed 0 still get a deterministic non-trivial sequence.
        self.source = GKMersenneTwisterRandomSource(seed: seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed)
    }

    public func next() -> UInt64 {
        let lo = UInt32(bitPattern: Int32(truncatingIfNeeded: source.nextInt()))
        let hi = UInt32(bitPattern: Int32(truncatingIfNeeded: source.nextInt()))
        return (UInt64(hi) << 32) | UInt64(lo)
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
