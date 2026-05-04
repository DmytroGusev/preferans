import Foundation

struct PreferansScoring {
    let players: [PlayerID]
    let rules: PreferansRules
    let match: MatchSettings

    func passedOut(_ whist: WhistState) -> DealResult {
        var delta = ScoreDelta(players: players)
        delta.addPool(whist.contract.value + whist.bonusPoolOnSuccess, to: whist.declarer)
        return .unplayed(
            kind: .passedOut,
            activePlayers: whist.activePlayers,
            scoreDelta: delta,
            initialHands: openingHands(from: whist)
        )
    }

    func halfWhist(_ whist: WhistState, halfWhister: PlayerID) -> DealResult {
        var delta = ScoreDelta(players: players)
        delta.addPool(whist.contract.value, to: whist.declarer)
        delta.addWhists(
            whist.contract.value * (effectiveWhistRequirement(for: whist.contract) / 2),
            writer: halfWhister,
            on: whist.declarer
        )
        return .unplayed(
            kind: .halfWhist(declarer: whist.declarer, contract: whist.contract, halfWhister: halfWhister),
            activePlayers: whist.activePlayers,
            scoreDelta: delta,
            initialHands: openingHands(from: whist)
        )
    }

    func completedPlay(_ playing: PlayingState, settlement: TrickSettlement? = nil) -> DealResult {
        switch playing.kind {
        case let .game(context):
            return scoreGame(playing, context: context, settlement: settlement)
        case let .misere(context):
            return scoreMisere(playing, context: context, settlement: settlement)
        case .allPass:
            return scoreAllPass(playing, settlement: settlement)
        }
    }

    private func scoreGame(
        _ playing: PlayingState,
        context: GamePlayContext,
        settlement: TrickSettlement? = nil
    ) -> DealResult {
        var delta = ScoreDelta(players: players)
        let declarerTricks = tricks(context.declarer, in: playing.trickCounts)
        let defenderTricks = context.defenders.reduce(0) { $0 + tricks($1, in: playing.trickCounts) }
        let value = context.contract.value

        if declarerTricks >= context.contract.tricks {
            delta.addPool(value + context.bonusPoolOnSuccess, to: context.declarer)
        } else {
            let undertricks = context.contract.tricks - declarerTricks
            delta.addMountain(value * undertricks, to: context.declarer)
            if rules.failedDeclarerConsolation == .eachDefender {
                for defender in context.defenders {
                    delta.addWhists(value * undertricks, writer: defender, on: context.declarer)
                }
            }
        }

        // Multi-whister and "own hand only" single-whister both credit each
        // writer with their own trick count. Greedy single-whister rolls
        // every defender trick into the lone writer.
        let usesGreedyAggregation = context.whisters.count == 1 && rules.singleWhistScoring == .greedy
        for whister in context.whisters {
            let whistTricks = usesGreedyAggregation
                ? defenderTricks
                : tricks(whister, in: playing.trickCounts)
            delta.addWhists(value * whistTricks, writer: whister, on: context.declarer)
        }

        if rules.whistResponsibility == .responsible {
            applyWhistResponsibility(
                contract: context.contract,
                whisters: context.whisters,
                trickCounts: playing.trickCounts,
                defenderTricks: defenderTricks,
                value: value,
                delta: &delta
            )
        }

        return DealResult(
            kind: .game(declarer: context.declarer, contract: context.contract, whisters: context.whisters),
            activePlayers: playing.activePlayers,
            trickCounts: playing.trickCounts,
            completedTricks: playing.completedTricks,
            scoreDelta: delta,
            initialHands: openingHands(from: playing),
            settlement: settlement
        )
    }

    private func applyWhistResponsibility(
        contract: GameContract,
        whisters: [PlayerID],
        trickCounts: [PlayerID: Int],
        defenderTricks: Int,
        value: Int,
        delta: inout ScoreDelta
    ) {
        guard !whisters.isEmpty else { return }
        let requirement = effectiveWhistRequirement(for: contract)
        guard requirement > 0 else { return }

        if whisters.count == 1, let whister = whisters.first {
            let missing = max(0, requirement - defenderTricks)
            delta.addMountain(missing * value, to: whister)
            return
        }

        if requirement == 1 {
            if defenderTricks == 0, let second = whisters.last {
                delta.addMountain(value, to: second)
            }
            return
        }

        let quota = requirement / max(1, whisters.count)
        for whister in whisters {
            let own = tricks(whister, in: trickCounts)
            let missing = max(0, quota - own)
            delta.addMountain(missing * value, to: whister)
        }
    }

    private func scoreMisere(
        _ playing: PlayingState,
        context: MiserePlayContext,
        settlement: TrickSettlement? = nil
    ) -> DealResult {
        var delta = ScoreDelta(players: players)
        let tricks = tricks(context.declarer, in: playing.trickCounts)
        if tricks == 0 {
            delta.addPool(10, to: context.declarer)
        } else {
            delta.addMountain(10 * tricks, to: context.declarer)
        }
        return DealResult(
            kind: .misere(declarer: context.declarer),
            activePlayers: playing.activePlayers,
            trickCounts: playing.trickCounts,
            completedTricks: playing.completedTricks,
            scoreDelta: delta,
            initialHands: openingHands(from: playing),
            settlement: settlement
        )
    }

    private func scoreAllPass(_ playing: PlayingState, settlement: TrickSettlement? = nil) -> DealResult {
        var delta = ScoreDelta(players: players)
        let multiplier: Int
        let amnesty: Bool
        switch rules.allPassPenaltyPolicy {
        case let .perTrick(m, a):
            multiplier = m
            amnesty = a
        }
        let minimum = playing.activePlayers.map { tricks($0, in: playing.trickCounts) }.min() ?? 0
        for player in playing.activePlayers {
            let tricks = tricks(player, in: playing.trickCounts)
            if tricks == 0, rules.zeroTricksAllPassPoolBonus > 0 {
                delta.addPool(rules.zeroTricksAllPassPoolBonus * multiplier, to: player)
            }
            let chargeable = amnesty ? max(0, tricks - minimum) : tricks
            delta.addMountain(chargeable * multiplier, to: player)
        }
        return DealResult(
            kind: .allPass,
            activePlayers: playing.activePlayers,
            trickCounts: playing.trickCounts,
            completedTricks: playing.completedTricks,
            scoreDelta: delta,
            initialHands: openingHands(from: playing),
            settlement: settlement
        )
    }

    private func effectiveWhistRequirement(for contract: GameContract) -> Int {
        if contract.tricks == 10 && match.totus.requireWhistOnTenTricks {
            return 1
        }
        return rules.whistRequirement(for: contract)
    }

    private func openingHands(from whist: WhistState) -> [PlayerID: [Card]]? {
        var hands = whist.hands
        restoreDeclarerOpeningHand(
            declarer: whist.declarer,
            talon: whist.talon,
            discard: whist.discard,
            hands: &hands
        )
        return validOpeningHands(hands, activePlayers: whist.activePlayers)
    }

    private func openingHands(from playing: PlayingState) -> [PlayerID: [Card]]? {
        var hands = playing.activePlayers.dictionary(filledWith: [Card]())
        for trick in playing.completedTricks {
            for play in trick.plays {
                hands[play.player, default: []].append(play.card)
            }
        }
        for play in playing.currentTrick {
            hands[play.player, default: []].append(play.card)
        }
        for player in playing.activePlayers {
            hands[player, default: []].append(contentsOf: playing.hands[player] ?? [])
        }

        switch playing.kind {
        case let .game(context):
            restoreDeclarerOpeningHand(
                declarer: context.declarer,
                talon: playing.talon,
                discard: playing.discard,
                hands: &hands
            )
        case let .misere(context):
            restoreDeclarerOpeningHand(
                declarer: context.declarer,
                talon: playing.talon,
                discard: playing.discard,
                hands: &hands
            )
        case .allPass:
            break
        }

        return validOpeningHands(hands, activePlayers: playing.activePlayers)
    }

    private func restoreDeclarerOpeningHand(
        declarer: PlayerID,
        talon: [Card],
        discard: [Card],
        hands: inout [PlayerID: [Card]]
    ) {
        hands[declarer, default: []].append(contentsOf: discard)
        for card in talon {
            if let index = hands[declarer]?.firstIndex(of: card) {
                hands[declarer]?.remove(at: index)
            }
        }
    }

    private func sortedHands(_ hands: [PlayerID: [Card]], activePlayers: [PlayerID]) -> [PlayerID: [Card]] {
        Dictionary(uniqueKeysWithValues: activePlayers.map { player in
            (player, (hands[player] ?? []).sorted())
        })
    }

    private func validOpeningHands(_ hands: [PlayerID: [Card]], activePlayers: [PlayerID]) -> [PlayerID: [Card]]? {
        guard Set(hands.keys) == Set(activePlayers) else { return nil }
        for player in activePlayers {
            let hand = hands[player] ?? []
            guard hand.count == 10, Set(hand).count == hand.count else { return nil }
        }
        return sortedHands(hands, activePlayers: activePlayers)
    }

    private func tricks(_ player: PlayerID, in trickCounts: [PlayerID: Int]) -> Int {
        guard let count = trickCounts[player] else {
            preconditionFailure("trickCounts missing entry for \(player) - invariant violated")
        }
        return count
    }
}
