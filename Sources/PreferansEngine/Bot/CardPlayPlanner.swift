import Foundation

/// Perfect-information Monte Carlo planner for card play. For each legal
/// candidate move the planner samples a number of fully-determined deals
/// consistent with the bot's information set, plays each deal out greedily,
/// and averages a contract-aware score. The move with the best mean score
/// wins.
public struct CardPlayPlanner: Sendable {
    public var samples: Int
    public var rolloutsPerSample: Int

    public init(samples: Int = 24, rolloutsPerSample: Int = 1) {
        self.samples = samples
        self.rolloutsPerSample = rolloutsPerSample
    }

    public func choose(snapshot: PreferansSnapshot, viewer: PlayerID) -> Card? {
        guard case .playing = snapshot.state,
              let engine = try? PreferansEngine(snapshot: snapshot),
              snapshot.state.currentActor == viewer else {
            return nil
        }
        let legal = engine.legalCards(for: viewer)
        if legal.count <= 1 { return legal.first }

        let sampler = DealSampler()
        var rng = SystemRandomNumberGenerator()
        let sampleSnapshots = sampler.samples(from: snapshot, viewer: viewer, count: samples, rng: &rng)
        // If sampling fails entirely (rare; only on contradictory void
        // inferences), fall back to the original snapshot — every hand is
        // already visible to the planner there.
        let pool = sampleSnapshots.isEmpty ? [snapshot] : sampleSnapshots

        var totals = [Double](repeating: 0, count: legal.count)
        var counts = [Int](repeating: 0, count: legal.count)
        for sample in pool {
            for (i, candidate) in legal.enumerated() {
                for _ in 0..<rolloutsPerSample {
                    totals[i] += rollout(from: sample, viewer: viewer, firstMove: candidate)
                    counts[i] += 1
                }
            }
        }

        var bestIndex = 0
        var bestMean = -Double.infinity
        for i in legal.indices {
            let mean = totals[i] / Double(max(1, counts[i]))
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
        firstMove: Card
    ) -> Double {
        guard var engine = try? PreferansEngine(snapshot: snapshot) else { return 0 }
        do {
            _ = try engine.apply(.playCard(player: viewer, card: firstMove))
        } catch {
            return -1_000 // illegal in this sample — heavily penalize
        }
        while case let .playing(p) = engine.state {
            let actor = p.currentPlayer
            let legal = engine.legalCards(for: actor)
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
    private func greedyChoice(
        legal: [Card],
        playing: PlayingState,
        actor: PlayerID
    ) -> Card {
        let trump = playing.kind.trumpSuit
        let wantsTricks = wantsTricks(actor: actor, kind: playing.kind)
        let leadSuit = playing.currentTrick.first?.card.suit

        if leadSuit == nil {
            return leadCard(legal: legal, trump: trump, wantsTricks: wantsTricks)
        }

        let currentBest = PreferansEngine.trickWinner(
            for: playing.currentTrick,
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
        case let .game(ctx): return actor == ctx.declarer
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

    /// Final score for a deal viewed from `viewer`. Higher is better;
    /// scaled in trick-equivalents so it's comparable across contracts.
    private func score(snapshot: PreferansSnapshot, viewer: PlayerID) -> Double {
        switch snapshot.state {
        case let .dealFinished(result):
            return scoreFromResult(result: result, viewer: viewer)
        case let .gameOver(summary):
            return scoreFromResult(result: summary.lastDeal, viewer: viewer)
        case let .playing(p):
            return scoreFromPlaying(playing: p, viewer: viewer)
        default:
            return 0
        }
    }

    private func scoreFromResult(result: DealResult, viewer: PlayerID) -> Double {
        let counts = result.trickCounts
        switch result.kind {
        case let .game(declarer, contract, _):
            let declarerTricks = counts[declarer] ?? 0
            if viewer == declarer {
                return Double(declarerTricks - contract.tricks) + (declarerTricks >= contract.tricks ? 5 : -5)
            } else {
                let made = declarerTricks >= contract.tricks
                return Double(counts[viewer] ?? 0) + (made ? -5 : 5)
            }
        case let .misere(declarer):
            let declarerTricks = counts[declarer] ?? 0
            if viewer == declarer {
                return Double(-declarerTricks * 2) + (declarerTricks == 0 ? 5 : -5)
            } else {
                return declarerTricks > 0 ? 5 : -1
            }
        case .allPass:
            let own = counts[viewer] ?? 0
            return Double(-own * 2) + (own == 0 ? 3 : 0)
        case .passedOut, .halfWhist:
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
