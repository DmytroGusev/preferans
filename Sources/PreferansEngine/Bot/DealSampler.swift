import Foundation

/// Builds randomized engine snapshots that look identical to `viewer` but
/// have plausible random opponent hands (and discard contents). The bot
/// uses these samples for perfect-information rollouts — each rollout
/// pretends the world it sees is real, plays it out, and votes on which
/// candidate move performs best on average.
public struct DealSampler {
    private static let fullDeck: Set<Card> = Set(Deck.standard32)

    public init() {}

    public func samples(
        from snapshot: PreferansSnapshot,
        viewer: PlayerID,
        count: Int,
        rng: inout SystemRandomNumberGenerator
    ) -> [PreferansSnapshot] {
        guard case let .playing(playing) = snapshot.state else {
            return Array(repeating: snapshot, count: count)
        }

        let voids = inferredVoids(in: playing)
        var results: [PreferansSnapshot] = []
        results.reserveCapacity(count)
        for _ in 0..<count {
            if let sampled = sampleOnce(snapshot: snapshot, playing: playing, viewer: viewer, voids: voids, rng: &rng) {
                results.append(sampled)
            }
        }
        return results
    }

    /// Per-seat suits a player is known to be void in, derived from any
    /// trick where they failed to follow lead suit despite the rules
    /// requiring it.
    public func inferredVoids(in playing: PlayingState) -> [PlayerID: Set<Suit>] {
        var voids: [PlayerID: Set<Suit>] = [:]
        let trump = playing.kind.trumpSuit
        for trick in playing.completedTricks {
            for play in trick.plays where play.card.suit != trick.leadSuit {
                voids[play.player, default: []].insert(trick.leadSuit)
                if let trump, play.card.suit != trump, trick.leadSuit != trump {
                    voids[play.player, default: []].insert(trump)
                }
            }
        }
        if let leadCard = playing.currentTrick.first?.card {
            let leadSuit = leadCard.suit
            for play in playing.currentTrick.dropFirst() where play.card.suit != leadSuit {
                voids[play.player, default: []].insert(leadSuit)
                if let trump, play.card.suit != trump, leadSuit != trump {
                    voids[play.player, default: []].insert(trump)
                }
            }
        }
        return voids
    }

    private func sampleOnce(
        snapshot: PreferansSnapshot,
        playing: PlayingState,
        viewer: PlayerID,
        voids: [PlayerID: Set<Suit>],
        rng: inout SystemRandomNumberGenerator
    ) -> PreferansSnapshot? {
        let viewerHand = playing.hands[viewer] ?? []
        let allPlayed = (playing.completedTricks.flatMap(\.plays) + playing.currentTrick).map(\.card)

        // Pool of cards the viewer cannot see. The talon is consumed before
        // play in game/misère; in all-pass it remains visible to everyone.
        var hidden = Self.fullDeck
        hidden.subtract(viewerHand)
        hidden.subtract(allPlayed)
        if case .allPass = playing.kind {
            hidden.subtract(playing.talon)
        }
        let discardKnown: Bool = {
            switch playing.kind {
            case let .game(ctx): return ctx.declarer == viewer
            case let .misere(ctx): return ctx.declarer == viewer
            case .allPass: return true
            }
        }()
        if discardKnown {
            hidden.subtract(playing.discard)
        }

        struct Slot {
            let kind: SlotKind
            var size: Int
            var allowed: Set<Suit>
        }
        enum SlotKind: Hashable {
            case seat(PlayerID)
            case discard
        }

        var slots: [Slot] = []
        for seat in playing.activePlayers where seat != viewer {
            let size = playing.hands[seat]?.count ?? 0
            guard size > 0 else { continue }
            let blocked = voids[seat] ?? []
            slots.append(Slot(kind: .seat(seat), size: size, allowed: Set(Suit.allCases).subtracting(blocked)))
        }
        if !discardKnown {
            slots.append(Slot(kind: .discard, size: playing.discard.count, allowed: Set(Suit.allCases)))
        }

        let demand = slots.reduce(0) { $0 + $1.size }
        guard hidden.count == demand else { return nil }

        // Slots with the smallest allowed suit set go first. With at most
        // one or two voids in play, the assignment converges in a couple
        // of attempts.
        slots.sort { lhs, rhs in
            if lhs.allowed.count != rhs.allowed.count {
                return lhs.allowed.count < rhs.allowed.count
            }
            return lhs.size > rhs.size
        }

        var pool = Array(hidden)
        let maxAttempts = 32
        var assignment: [SlotKind: [Card]]?
        attemptLoop: for _ in 0..<maxAttempts {
            pool.shuffle(using: &rng)
            var bySuit: [Suit: [Card]] = [:]
            for c in pool { bySuit[c.suit, default: []].append(c) }

            var result: [SlotKind: [Card]] = [:]
            for slot in slots {
                var taken: [Card] = []
                taken.reserveCapacity(slot.size)
                while taken.count < slot.size {
                    let candidateSuits = slot.allowed.filter { !(bySuit[$0]?.isEmpty ?? true) }
                    if candidateSuits.isEmpty { continue attemptLoop }
                    // Pick the suit with the most remaining cards so the
                    // residual pool stays balanced across suits.
                    let suit = candidateSuits.max(by: { (bySuit[$0]?.count ?? 0) < (bySuit[$1]?.count ?? 0) })!
                    taken.append(bySuit[suit]!.removeLast())
                }
                result[slot.kind] = taken
            }
            assignment = result
            break
        }
        guard let assignment else { return nil }

        var newPlaying = playing
        for (kind, cards) in assignment {
            switch kind {
            case let .seat(seat):
                newPlaying.hands[seat] = cards.sorted()
            case .discard:
                newPlaying.discard = cards.sorted()
            }
        }

        var newSnapshot = snapshot
        newSnapshot.state = .playing(newPlaying)
        return newSnapshot
    }
}
