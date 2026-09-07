import Foundation

/// Builds randomized engine snapshots that look identical to `viewer` but
/// have plausible random opponent hands (and discard contents). The bot
/// uses these samples for perfect-information rollouts — each rollout
/// pretends the world it sees is real, plays it out, and votes on which
/// candidate move performs best on average.
public struct DealSampler {
    private static let fullDeck: Set<Card> = Set(Deck.standard32)

    fileprivate enum SlotKind: Hashable {
        case seat(PlayerID)
        case discard
        case talon
    }

    fileprivate struct Slot {
        let kind: SlotKind
        var size: Int
        var allowed: Set<Suit>
        var forbiddenCards: Set<Card>
        let insertionOrdinal: Int

        func accepts(_ card: Card) -> Bool {
            allowed.contains(card.suit) && !forbiddenCards.contains(card)
        }
    }

    public init() {}

    public func samples<RNG: RandomNumberGenerator>(
        from snapshot: PreferansSnapshot,
        viewer: PlayerID,
        count: Int,
        rng: inout RNG
    ) -> [PreferansSnapshot] {
        guard count > 0, case let .playing(playing) = snapshot.state else { return [] }

        let voids = inferredVoids(in: playing)
        // Hands the viewer can legitimately see: their own and any seat
        // they're currently controlling (open single-whist dummy play).
        // Everything else stays in the hidden pool that the sampler
        // scrambles.
        var visibleSeats: Set<PlayerID> = [viewer]
        for seat in playing.activePlayers where seat != viewer {
            if playing.controllingActor(of: seat, rules: snapshot.rules) == viewer {
                visibleSeats.insert(seat)
            }
        }
        if case let .game(context) = playing.kind {
            if context.defenderPlayMode == .open {
                visibleSeats.formUnion(context.defenders)
            }
            if context.contract.tricks == 10 && context.whisters.isEmpty && context.whistCalls.isEmpty {
                visibleSeats.formUnion(playing.activePlayers)
            }
        }
        // Closed misère plays the defenders' hands open: every seat —
        // declarer and both defenders — can legitimately see the
        // defenders' cards, so they must not be scrambled into the hidden
        // pool. Only the declarer's hand stays concealed.
        if case let .misere(context) = playing.kind {
            for seat in playing.activePlayers where seat != context.declarer {
                visibleSeats.insert(seat)
            }
        }
        var results: [PreferansSnapshot] = []
        results.reserveCapacity(count)
        for _ in 0..<count {
            if let sampled = sampleOnce(
                snapshot: snapshot,
                playing: playing,
                viewer: viewer,
                visibleSeats: visibleSeats,
                voids: voids,
                rng: &rng
            ) {
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
        if let leadSuit = playing.requiredSuit {
            for play in playing.currentTrick where play.card.suit != leadSuit {
                voids[play.player, default: []].insert(leadSuit)
                if let trump, play.card.suit != trump, leadSuit != trump {
                    voids[play.player, default: []].insert(trump)
                }
            }
        }
        return voids
    }

    private func sampleOnce<RNG: RandomNumberGenerator>(
        snapshot: PreferansSnapshot,
        playing: PlayingState,
        viewer: PlayerID,
        visibleSeats: Set<PlayerID>,
        voids: [PlayerID: Set<Suit>],
        rng: inout RNG
    ) -> PreferansSnapshot? {
        let allPlayed = (playing.completedTricks.flatMap(\.plays) + playing.currentTrick).map(\.card)

        // Raspasy reveals one talon lead at a time, or conceals both cards
        // under hidden-talon rules. Previously revealed leads remain known.
        let revealedTalonCount: Int = {
            guard case .allPass = playing.kind, playing.usesTalonLeads else { return 0 }
            return min(playing.talon.count, playing.completedTricks.count + 1)
        }()
        // Pool of cards outside the viewer's public/private information set.
        var hidden = Self.fullDeck
        for seat in visibleSeats {
            hidden.subtract(playing.hands[seat] ?? [])
        }
        hidden.subtract(allPlayed)
        if case .allPass = playing.kind {
            hidden.subtract(playing.talon.prefix(revealedTalonCount))
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

        var slots: [Slot] = []
        let declarer = snapshot.state.declarer
        // Everyone saw the exchanged talon. Unplayed talon cards can only
        // remain with the declarer or in the discard, never an opponent hand.
        let exchangedTalon = declarer == nil ? Set<Card>() : Set(playing.talon)
        for seat in playing.activePlayers where !visibleSeats.contains(seat) {
            let size = playing.hands[seat]?.count ?? 0
            guard size > 0 else { continue }
            let blocked = voids[seat] ?? []
            slots.append(Slot(
                kind: .seat(seat),
                size: size,
                allowed: Set(Suit.allCases).subtracting(blocked),
                forbiddenCards: seat == declarer ? [] : exchangedTalon,
                insertionOrdinal: slots.count
            ))
        }
        if !discardKnown {
            slots.append(Slot(
                kind: .discard,
                size: playing.discard.count,
                allowed: Set(Suit.allCases),
                forbiddenCards: [],
                insertionOrdinal: slots.count
            ))
        }
        if case .allPass = playing.kind, revealedTalonCount < playing.talon.count {
            slots.append(Slot(
                kind: .talon,
                size: playing.talon.count - revealedTalonCount,
                allowed: Set(Suit.allCases),
                forbiddenCards: [],
                insertionOrdinal: slots.count
            ))
        }

        let demand = slots.reduce(0) { $0 + $1.size }
        guard hidden.count == demand else { return nil }

        // Fill the most constrained slots first, retrying bounded random
        // assignments when a later slot cannot be filled.
        slots.sort { lhs, rhs in
            let leftCapacity = hidden.filter(lhs.accepts).count
            let rightCapacity = hidden.filter(rhs.accepts).count
            if leftCapacity != rightCapacity {
                return leftCapacity < rightCapacity
            }
            if lhs.size != rhs.size {
                return lhs.size > rhs.size
            }
            return lhs.insertionOrdinal < rhs.insertionOrdinal
        }

        // Set iteration order is intentionally unspecified. Canonicalize the
        // pool before applying seeded randomness so equal seeds produce equal
        // samples across process launches and platforms.
        var pool = hidden.sorted()
        let maxAttempts = 32
        var assignment: [SlotKind: [Card]]?
        attemptLoop: for _ in 0..<maxAttempts {
            pool.shuffle(using: &rng)
            var remaining = pool
            var result: [SlotKind: [Card]] = [:]
            for slot in slots {
                let taken = Array(remaining.lazy.filter(slot.accepts).prefix(slot.size))
                guard taken.count == slot.size else { continue attemptLoop }
                let used = Set(taken)
                remaining.removeAll { used.contains($0) }
                result[slot.kind] = taken
            }
            assignment = result
            break
        }
        guard let assignment else { return nil }

        var newHands = playing.hands
        var newDiscard = playing.discard
        var newTalon = playing.talon
        for (kind, cards) in assignment {
            switch kind {
            case let .seat(seat):
                newHands[seat] = cards.sorted()
            case .discard:
                newDiscard = cards.sorted()
            case .talon:
                newTalon = Array(playing.talon.prefix(revealedTalonCount)) + cards
            }
        }

        var newSnapshot = snapshot
        newSnapshot.state = .playing(PlayingState(
            dealer: playing.dealer, activePlayers: playing.activePlayers,
            hands: newHands, talon: newTalon, discard: newDiscard,
            leader: playing.leader, currentPlayer: playing.currentPlayer,
            currentTrick: playing.currentTrick, completedTricks: playing.completedTricks,
            trickCounts: playing.trickCounts, kind: playing.kind,
            pendingSettlement: playing.pendingSettlement
        ))
        return newSnapshot
    }
}
