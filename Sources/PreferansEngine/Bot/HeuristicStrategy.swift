import Foundation

/// Default semi-competent bot strategy.
///
/// Bidding, contract declaration, discard, and whist use a calibrated
/// hand evaluator with simple thresholds — fast, deterministic, no
/// sampling. Card play uses ``CardPlayPlanner`` (perfect-info Monte
/// Carlo) so the bot accounts for hidden hands when it actually matters.
public struct HeuristicStrategy: PlayerStrategy {
    public var planner: CardPlayPlanner

    public init(planner: CardPlayPlanner = CardPlayPlanner()) {
        self.planner = planner
    }

    public func decide(
        snapshot: PreferansSnapshot,
        viewer: PlayerID
    ) async -> PreferansAction? {
        switch snapshot.state {
        case .waitingForDeal, .dealFinished, .gameOver:
            return nil
        case let .bidding(s):
            guard s.currentPlayer == viewer else { return nil }
            return .bid(player: viewer, call: chooseBid(snapshot: snapshot, hand: s.hands[viewer] ?? [], viewer: viewer))
        case let .awaitingDiscard(s):
            guard s.declarer == viewer else { return nil }
            return .discard(player: viewer, cards: chooseDiscard(state: s, viewer: viewer))
        case let .awaitingContract(s):
            guard s.declarer == viewer else { return nil }
            return .declareContract(player: viewer, contract: chooseContract(snapshot: snapshot, hand: s.hands[viewer] ?? [], viewer: viewer))
        case let .awaitingWhist(s):
            guard s.currentPlayer == viewer else { return nil }
            return .whist(player: viewer, call: chooseWhistCall(snapshot: snapshot, state: s, viewer: viewer))
        case let .awaitingDefenderMode(s):
            guard s.whister == viewer else { return nil }
            return .chooseDefenderMode(player: viewer, mode: .closed)
        case let .playing(s):
            guard s.currentPlayer == viewer else { return nil }
            let card = planner.choose(snapshot: snapshot, viewer: viewer)
                ?? (try? PreferansEngine(snapshot: snapshot).legalCards(for: viewer))?.first
            guard let card else { return nil }
            return .playCard(player: viewer, card: card)
        }
    }

    // MARK: Bidding

    private func chooseBid(
        snapshot: PreferansSnapshot,
        hand: [Card],
        viewer: PlayerID
    ) -> BidCall {
        guard let engine = try? PreferansEngine(snapshot: snapshot) else { return .pass }
        let legal = engine.legalBidCalls(for: viewer)
        guard !legal.isEmpty else { return .pass }
        let grouped = HandEvaluator.groupBySuit(hand)
        var best: ContractBid? = nil
        for call in legal {
            guard case let .bid(bid) = call, bidIsAffordable(bid: bid, grouped: grouped) else { continue }
            if best == nil || bid > best! { best = bid }
        }
        if let best { return .bid(best) }
        return .pass
    }

    private func bidIsAffordable(bid: ContractBid, grouped: HandEvaluator.SuitGrouping) -> Bool {
        switch bid {
        case let .game(contract):
            // The bot bids before discard, so it will gain ~1 useful card
            // from the talon on average; bonus reflects that.
            let estimate = HandEvaluator.expectedDeclarerTricks(grouped: grouped, trump: contract.strain.suit) + 0.75
            let margin: Double
            switch contract.tricks {
            case 6: margin = 0.0
            case 7: margin = 0.25
            case 8: margin = 0.5
            case 9: margin = 1.0
            default: margin = 1.5
            }
            return estimate >= Double(contract.tricks) - margin
        case .misere:
            return HandEvaluator.expectedMisereTricks(grouped: grouped) <= 0.5
        case .totus:
            // Totus needs all 10 tricks — only the strongest hands.
            let bestStrain = Strain.allStandard
                .map { HandEvaluator.expectedDeclarerTricks(grouped: grouped, trump: $0.suit) }
                .max() ?? 0
            return bestStrain + 0.75 >= 9.5
        }
    }

    // MARK: Discard + Contract

    private func chooseDiscard(state: ExchangeState, viewer: PlayerID) -> [Card] {
        let combined = (state.hands[viewer] ?? []) + state.talon
        switch state.finalBid {
        case .misere:
            return bestPair(in: combined, comparator: <) { kept in
                HandEvaluator.expectedMisereTricks(grouped: HandEvaluator.groupBySuit(kept))
            }
        case .game, .totus:
            return bestPair(in: combined, comparator: >) { kept in
                let grouped = HandEvaluator.groupBySuit(kept)
                return Strain.allStandard
                    .map { HandEvaluator.expectedDeclarerTricks(grouped: grouped, trump: $0.suit) }
                    .max() ?? 0
            }
        }
    }

    /// Iterates every unordered pair from `cards` and returns the pair
    /// whose *kept* hand (the rest) optimizes `score` under `comparator`.
    /// Pass `>` to maximize score, `<` to minimize.
    private func bestPair(
        in cards: [Card],
        comparator: (Double, Double) -> Bool,
        score: ([Card]) -> Double
    ) -> [Card] {
        guard cards.count >= 2 else { return Array(cards.prefix(2)) }
        var bestScore: Double = comparator(1, 0) ? -.infinity : .infinity
        var bestPair: [Card] = [cards[0], cards[1]]
        var kept: [Card] = []
        kept.reserveCapacity(cards.count - 2)
        for i in 0..<cards.count {
            for j in (i + 1)..<cards.count {
                kept.removeAll(keepingCapacity: true)
                for k in 0..<cards.count where k != i && k != j {
                    kept.append(cards[k])
                }
                let s = score(kept)
                if comparator(s, bestScore) {
                    bestScore = s
                    bestPair = [cards[i], cards[j]]
                }
            }
        }
        return bestPair
    }

    private func chooseContract(
        snapshot: PreferansSnapshot,
        hand: [Card],
        viewer: PlayerID
    ) -> GameContract {
        guard let engine = try? PreferansEngine(snapshot: snapshot) else {
            return GameContract(6, .suit(.spades))
        }
        let legal = engine.legalContractDeclarations(for: viewer)
        guard !legal.isEmpty else { return GameContract(6, .suit(.spades)) }
        let grouped = HandEvaluator.groupBySuit(hand)

        var best: GameContract = legal.first!
        var bestScore = -Double.infinity
        for c in legal {
            let estimate = HandEvaluator.expectedDeclarerTricks(grouped: grouped, trump: c.strain.suit)
            // Made contracts are weighted by pool value + slack; failing
            // contracts get a penalty proportional to undertricks so the
            // bot doesn't chase what it can't make.
            let made = estimate - Double(c.tricks)
            let weight: Double = made >= 0 ? Double(c.value) + made : made * 5
            if weight > bestScore {
                bestScore = weight
                best = c
            }
        }
        return best
    }

    // MARK: Whist

    private func chooseWhistCall(
        snapshot: PreferansSnapshot,
        state: WhistState,
        viewer: PlayerID
    ) -> WhistCall {
        guard let engine = try? PreferansEngine(snapshot: snapshot) else { return .pass }
        let legal = engine.legalWhistCalls(for: viewer)
        guard !legal.isEmpty else { return .pass }
        let hand = state.hands[viewer] ?? []
        let estimate = HandEvaluator.expectedDefenderTricks(hand: hand, trump: state.contract.strain.suit)
        let requirement = snapshot.rules.whistRequirement(for: state.contract)
        // Per-defender share of the team's whist requirement — for a
        // 6-trick contract that's 4/2 = 2 tricks each.
        let share = max(1.0, Double(requirement) / 2.0)
        if legal.contains(.whist), estimate >= share { return .whist }
        if legal.contains(.halfWhist), estimate >= share - 0.75 { return .halfWhist }
        return .pass
    }
}
