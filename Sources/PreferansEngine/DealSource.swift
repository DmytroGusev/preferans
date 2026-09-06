import Foundation

/// Deterministic, cross-platform xoshiro256** generator. Keeping this in pure
/// Swift lets the exact same engine run on Apple devices, Linux servers, and
/// WebAssembly without depending on Apple-only GameplayKit.
///
/// Reference type so that copies share state — multiple
/// `shuffled(using:)` calls advance the same sequence, which makes
/// scripted tests both deterministic and easy to reason about across
/// deals.
public final class SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: (UInt64, UInt64, UInt64, UInt64)

    public init(seed: UInt64) {
        var mixer = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
        func splitMix64() -> UInt64 {
            mixer &+= 0x9E37_79B9_7F4A_7C15
            var value = mixer
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }
        self.state = (splitMix64(), splitMix64(), splitMix64(), splitMix64())
    }

    public func next() -> UInt64 {
        let result = (state.1 &* 5).rotatedLeft(by: 7) &* 9
        let temporary = state.1 << 17

        state.2 ^= state.0
        state.3 ^= state.1
        state.1 ^= state.2
        state.0 ^= state.3
        state.2 ^= temporary
        state.3 = state.3.rotatedLeft(by: 45)

        return result
    }
}

private extension UInt64 {
    func rotatedLeft(by distance: UInt64) -> UInt64 {
        (self << distance) | (self >> (64 - distance))
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
///
/// Sendable because deal sources cross actor boundaries on their way to
/// `HostGameActor` / online coordinators. Stateful implementations serialize
/// their RNG/index mutation internally; callers do not need to supply an
/// actor-isolation guarantee that the protocol cannot enforce.
public protocol DealSource: AnyObject, Sendable {
    func nextDeck() -> [Card]
}

/// Stateless, so checked `Sendable` conformance is sufficient.
public final class RandomDealSource: DealSource {
    public init() {}
    public func nextDeck() -> [Card] {
        Deck.standard32.shuffled()
    }
}

public final class SeededDealSource: DealSource, @unchecked Sendable {
    private var rng: SeededRandomNumberGenerator
    /// Protects the reference-backed deterministic RNG. The conformance remains
    /// unchecked because Swift cannot infer synchronization around `rng`.
    private let lock = NSLock()

    public init(seed: UInt64) {
        self.rng = SeededRandomNumberGenerator(seed: seed)
    }

    public func nextDeck() -> [Card] {
        lock.lock()
        defer { lock.unlock() }
        return Deck.standard32.shuffled(using: &rng)
    }
}

public final class ScriptedDealSource: DealSource, @unchecked Sendable {
    private let decks: [[Card]]
    private var index = 0
    /// Protects the cycling cursor. `decks` is immutable value state.
    private let lock = NSLock()

    public init(decks: [[Card]]) {
        precondition(!decks.isEmpty, "ScriptedDealSource requires at least one deck")
        self.decks = decks
    }

    public func nextDeck() -> [Card] {
        lock.lock()
        defer { lock.unlock() }
        defer { index += 1 }
        return decks[index % decks.count]
    }
}
