import Foundation

/// Perfect-information Monte Carlo planner for card play. For each legal
/// candidate move the planner samples a number of fully-determined deals
/// consistent with the bot's information set, plays each deal out greedily,
/// and averages a contract-aware score. The move with the best mean score
/// wins.
public struct CardPlayPlanner: Sendable {
    public var samples: Int
    public var samplingSeed: UInt64

    public init(
        samples: Int = 24,
        samplingSeed: UInt64 = 0x5052_4546_4552_414E
    ) {
        self.samples = max(1, samples)
        self.samplingSeed = samplingSeed
    }

    public func choose(snapshot: PreferansSnapshot, viewer: PlayerID) -> Card? {
        guard case .playing = snapshot.state,
              let engine = try? PreferansEngine(snapshot: snapshot),
              let currentActor = snapshot.state.currentActor,
              engine.controllingActor(of: currentActor) == viewer else {
            return nil
        }
        // The card legally comes from `currentActor`'s hand — which may be
        // an open dummy hand the viewer is controlling. Rollout plays speak
        // for the seat that owns the card, not the bot's own seat.
        let actingFor = currentActor
        let legal = engine.legalCards(for: viewer)
        if legal.count <= 1 { return legal.first }

        let sampler = DealSampler()
        // Recreate the generator for each decision so this planner remains a
        // pure function of its snapshot, viewer, and configuration. Besides
        // making tests reproducible, hosts that independently evaluate the
        // same position cannot drift because of prior bot decisions.
        var rng = SeededRandomNumberGenerator(seed: samplingSeed)
        let sampleSnapshots = sampler.samples(from: snapshot, viewer: viewer, count: samples, rng: &rng)
        // If sampling fails entirely (rare; only on contradictory void
        // inferences), fall back to the original snapshot — every hand is
        // already visible to the planner there.
        let pool = sampleSnapshots.isEmpty ? [snapshot] : sampleSnapshots

        var totals = [Double](repeating: 0, count: legal.count)
        for sample in pool {
            for (i, candidate) in legal.enumerated() {
                totals[i] += rollout(from: sample, viewer: viewer, actingFor: actingFor, firstMove: candidate)
            }
        }

        var bestIndex = 0
        var bestMean = -Double.infinity
        for i in legal.indices {
            let mean = totals[i] / Double(pool.count)
            if mean > bestMean || (mean == bestMean && legal[i] < legal[bestIndex]) {
                bestMean = mean
                bestIndex = i
            }
        }
        return legal[bestIndex]
    }

    private func rollout(
        from snapshot: PreferansSnapshot,
        viewer: PlayerID,
        actingFor: PlayerID,
        firstMove: Card
    ) -> Double {
        guard var engine = try? PreferansEngine(snapshot: snapshot) else { return 0 }
        do {
            _ = try engine.apply(.playCard(player: actingFor, card: firstMove))
        } catch {
            return -1_000 // illegal in this sample — heavily penalize
        }
        while case let .playing(p) = engine.state {
            let actor = p.currentPlayer
            let controller = engine.controllingActor(of: actor)
            let legal = engine.legalCards(for: controller)
            guard !legal.isEmpty else { break }
            let move = greedyChoice(legal: legal, playing: p, actor: actor)
            do {
                _ = try engine.apply(.playCard(player: actor, card: move))
            } catch {
                break
            }
        }
        return score(snapshot: engine.snapshot, viewer: viewer)
    }

    /// Greedy in-rollout policy — used for both the bot itself and every
    /// opponent during simulation. Trick-winning vs trick-dumping based on
    /// whether the seat wants tricks under the active contract.
    func greedyChoice(
        legal: [Card],
        playing: PlayingState,
        actor: PlayerID
    ) -> Card {
        let trump = playing.kind.trumpSuit
        let wantsTricks = wantsTricks(actor: actor, kind: playing.kind)
        let talonLead = playing.currentTalonLead
        let leadSuit = talonLead?.card.suit ?? playing.currentTrick.first?.card.suit

        if leadSuit == nil {
            return leadCard(legal: legal, trump: trump, wantsTricks: wantsTricks)
        }

        let playsSoFar = (talonLead.map { [$0] } ?? []) + playing.currentTrick
        let currentBest = PreferansEngine.trickWinner(
            for: playsSoFar,
            leadSuit: leadSuit!,
            trump: trump
        )
        let teammateWinning = isTeammate(of: actor, candidate: currentBest.player, kind: playing.kind)
        return followCard(
            legal: legal,
            currentBest: currentBest.card,
            leadSuit: leadSuit!,
            trump: trump,
            wantsTricks: wantsTricks,
            teammateWinning: teammateWinning
        )
    }

    private func leadCard(legal: [Card], trump: Suit?, wantsTricks: Bool) -> Card {
        if wantsTricks, let cashable = legal.filter({ $0.suit != trump && $0.rank == .ace }).min() {
            return cashable
        }
        // Lead the lowest non-trump first (preserve trumps for ruffing);
        // ties broken by suit order for deterministic play.
        return legal.min { lhs, rhs in
            let lhsTrump = lhs.suit == trump
            let rhsTrump = rhs.suit == trump
            if lhsTrump != rhsTrump { return !lhsTrump }
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.suit < rhs.suit
        } ?? legal[0]
    }

    private func followCard(
        legal: [Card],
        currentBest: Card,
        leadSuit: Suit,
        trump: Suit?,
        wantsTricks: Bool,
        teammateWinning: Bool
    ) -> Card {
        // Single pass: track the cheapest winner and the highest non-winner
        // simultaneously, plus overall min/max for fallbacks.
        var cheapestWinner: Card?
        var highestLoser: Card?
        var minCard: Card = legal[0]
        var maxCard: Card = legal[0]
        for card in legal {
            if card < minCard { minCard = card }
            if card > maxCard { maxCard = card }
            let beats = PreferansEngine.compare(currentBest, card, leadSuit: leadSuit, trump: trump) == .orderedAscending
            if beats {
                if cheapestWinner == nil || card < cheapestWinner! { cheapestWinner = card }
            } else {
                if highestLoser == nil || card > highestLoser! { highestLoser = card }
            }
        }

        if wantsTricks && teammateWinning { return minCard }
        if wantsTricks { return cheapestWinner ?? minCard }
        return highestLoser ?? maxCard
    }

    private func wantsTricks(actor: PlayerID, kind: PlayKind) -> Bool {
        switch kind {
        case .game: return true
        case .misere, .allPass: return false
        }
    }

    private func isTeammate(of actor: PlayerID, candidate: PlayerID, kind: PlayKind) -> Bool {
        switch kind {
        case let .game(ctx):
            if actor == ctx.declarer || candidate == ctx.declarer { return false }
            return ctx.defenders.contains(actor) && ctx.defenders.contains(candidate)
        case .misere, .allPass:
            return false
        }
    }

    /// Final match balance for `viewer`. This deliberately uses the same
    /// pool/mountain/whist conversion as the production scoreboard, including
    /// variant-specific values and pulka closure already applied by the
    /// engine. Candidate cards are therefore compared by real Preferans value
    /// rather than an unrelated hard-coded trick bonus.
    private func score(snapshot: PreferansSnapshot, viewer: PlayerID) -> Double {
        switch snapshot.state {
        case .dealFinished, .gameOver:
            let balances = snapshot.score.normalizedBalances(
                poolPointValue: Double(snapshot.rules.poolPointWhistValue),
                mountainPointValue: Double(snapshot.rules.mountainPointWhistValue)
            )
            return balances[viewer] ?? 0
        case let .playing(p):
            return scoreFromPlaying(playing: p, viewer: viewer)
        default:
            return 0
        }
    }

    private func scoreFromPlaying(playing: PlayingState, viewer: PlayerID) -> Double {
        // Reached only when a rollout fails to terminate (illegal-move
        // bailout). Use partial counts as a fallback signal.
        let counts = playing.trickCounts
        switch playing.kind {
        case let .game(ctx):
            return viewer == ctx.declarer
                ? Double((counts[ctx.declarer] ?? 0) - ctx.contract.tricks)
                : Double(counts[viewer] ?? 0)
        case .misere:
            return Double(-(counts[viewer] ?? 0) * 2)
        case .allPass:
            return Double(-(counts[viewer] ?? 0))
        }
    }
}
