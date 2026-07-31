import Foundation

struct PreferansScoring {
    let players: [PlayerID]
    let rules: PreferansRules
    let match: MatchSettings
    let consecutiveAllPassDeals: Int

    init(
        players: [PlayerID],
        rules: PreferansRules,
        match: MatchSettings,
        consecutiveAllPassDeals: Int = 0
    ) {
        self.players = players
        self.rules = rules
        self.match = match
        self.consecutiveAllPassDeals = consecutiveAllPassDeals
    }

    func passedOut(_ whist: WhistState) -> DealResult {
        var delta = ScoreDelta(players: players)
        delta.addPool(poolValue(whist.contract) + whist.bonusPoolOnSuccess, to: whist.declarer)
        applyDealerGameTalonCompensation(
            dealer: whist.dealer,
            activePlayers: whist.activePlayers,
            talon: whist.talon,
            declarer: whist.declarer,
            contract: whist.contract,
            delta: &delta
        )
        return .unplayed(
            kind: .passedOut,
            activePlayers: whist.activePlayers,
            scoreDelta: delta,
            initialHands: openingHands(from: whist)
        )
    }

    func halfWhist(_ whist: WhistState, halfWhister: PlayerID) -> DealResult {
        var delta = ScoreDelta(players: players)
        delta.addPool(poolValue(whist.contract), to: whist.declarer)
        delta.addWhists(
            whistValue(whist.contract) * (effectiveWhistRequirement(for: whist.contract) / 2),
            writer: halfWhister,
            on: whist.declarer
        )
        applyDealerGameTalonCompensation(
            dealer: whist.dealer,
            activePlayers: whist.activePlayers,
            talon: whist.talon,
            declarer: whist.declarer,
            contract: whist.contract,
            delta: &delta
        )
        return .unplayed(
            kind: .halfWhist(declarer: whist.declarer, contract: whist.contract, halfWhister: halfWhister),
            activePlayers: whist.activePlayers,
            scoreDelta: delta,
            initialHands: openingHands(from: whist)
        )
    }

    func withoutThree(_ declaration: ContractDeclarationState) -> DealResult {
        var delta = ScoreDelta(players: players)
        delta.addMountain(
            declaration.finalBid.value * rules.mountainValueMultiplier * 3,
            to: declaration.declarer
        )
        return .unplayed(
            kind: .withoutThree(declarer: declaration.declarer, bid: declaration.finalBid),
            activePlayers: declaration.activePlayers,
            scoreDelta: delta,
            initialHands: openingHands(from: declaration)
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
        let poolUnit = poolValue(context.contract)
        let mountainUnit = mountainValue(context.contract)
        let whistUnit = whistValue(context.contract)

        if declarerTricks >= context.contract.tricks {
            delta.addPool(poolUnit + context.bonusPoolOnSuccess, to: context.declarer)
        } else {
            let undertricks = context.contract.tricks - declarerTricks
            delta.addMountain(mountainUnit * undertricks, to: context.declarer)
            applyDeclarerRemiseConsolation(
                undertricks: undertricks,
                context: context,
                whistValue: whistUnit,
                delta: &delta
            )
        }

        switch rules.singleWhistScoring {
        case .greedy where context.whisters.count == 1:
            delta.addWhists(whistUnit * defenderTricks, writer: context.whisters[0], on: context.declarer)
        case .gentleman where context.whisters.count == 1:
            let share = whistUnit * defenderTricks / context.defenders.count
            for defender in context.defenders {
                delta.addWhists(share, writer: defender, on: context.declarer)
            }
        case .greedy, .ownHandOnly, .gentleman:
            for whister in context.whisters {
                delta.addWhists(
                    whistUnit * tricks(whister, in: playing.trickCounts),
                    writer: whister,
                    on: context.declarer
                )
            }
        }

        if rules.whistResponsibility != .none {
            applyWhistResponsibility(
                contract: context.contract,
                whisters: context.whisters,
                trickCounts: playing.trickCounts,
                defenderTricks: defenderTricks,
                mountainValue: mountainUnit,
                delta: &delta
            )
        }

        applyDealerGameTalonCompensation(
            dealer: playing.dealer,
            activePlayers: playing.activePlayers,
            talon: playing.talon,
            declarer: context.declarer,
            contract: context.contract,
            delta: &delta
        )

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
        mountainValue: Int,
        delta: inout ScoreDelta
    ) {
        guard !whisters.isEmpty else { return }
        let requirement = effectiveWhistRequirement(for: contract)
        guard requirement > 0 else { return }

        if whisters.count == 1, let whister = whisters.first {
            let missing = max(0, requirement - defenderTricks)
            delta.addMountain(
                whistRemiseMountain(missing: missing, mountainValue: mountainValue),
                to: whister
            )
            return
        }

        // Two whisters defend as one partnership. If their combined tricks
        // meet the contract quota, neither is penalized even when one took
        // less than their nominal half-share.
        guard defenderTricks < requirement else { return }

        if requirement == 1 {
            if defenderTricks == 0, let second = whisters.last {
                delta.addMountain(
                    whistRemiseMountain(missing: 1, mountainValue: mountainValue),
                    to: second
                )
            }
            return
        }

        let quota = requirement / max(1, whisters.count)
        for whister in whisters {
            let own = tricks(whister, in: trickCounts)
            guard own < quota else { continue }
            // When the partnership missed its target, falling below the
            // half-share is a fixed one-unit whist remise, not one penalty
            // per individually missing trick.
            delta.addMountain(
                whistRemiseMountain(missing: 1, mountainValue: mountainValue),
                to: whister
            )
        }
    }

    private func whistRemiseMountain(missing: Int, mountainValue: Int) -> Int {
        switch rules.whistResponsibility {
        case .responsible:
            return missing * mountainValue
        case .semiResponsible:
            return missing * mountainValue / 2
        case .none:
            return 0
        }
    }

    private func scoreMisere(
        _ playing: PlayingState,
        context: MiserePlayContext,
        settlement: TrickSettlement? = nil
    ) -> DealResult {
        var delta = ScoreDelta(players: players)
        let declarerTricks = tricks(context.declarer, in: playing.trickCounts)
        if declarerTricks == 0 {
            delta.addPool(10 * rules.poolValueMultiplier, to: context.declarer)
        } else {
            delta.addMountain(
                10 * rules.mountainValueMultiplier * declarerTricks,
                to: context.declarer
            )
        }
        applyDealerMisereTalonCompensation(
            dealer: playing.dealer,
            activePlayers: playing.activePlayers,
            talon: playing.talon,
            declarer: context.declarer,
            delta: &delta
        )
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
        let baseMultiplier: Int
        let amnesty: Bool
        switch rules.allPassPenaltyPolicy {
        case let .perTrick(m, a):
            baseMultiplier = m
            amnesty = a
        }
        let multiplier = baseMultiplier
            * match.raspasy.scoreMultiplier(precededBy: consecutiveAllPassDeals)
        let scoringPlayers = playing.trickTakingPlayers
        let minimum = scoringPlayers.map { tricks($0, in: playing.trickCounts) }.min() ?? 0
        for player in scoringPlayers {
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
        if contract.tricks == 10
            && (match.totus.requireWhistOnTenTricks || rules.requireWhistOnTenTrickContracts) {
            return 1
        }
        return rules.whistRequirement(for: contract)
    }

    private func poolValue(_ contract: GameContract) -> Int {
        contract.value * rules.poolValueMultiplier
    }

    private func mountainValue(_ contract: GameContract) -> Int {
        contract.value * rules.mountainValueMultiplier
    }

    private func whistValue(_ contract: GameContract) -> Int {
        contract.value * rules.whistValueMultiplier
    }

    private func applyDealerGameTalonCompensation(
        dealer: PlayerID,
        activePlayers: [PlayerID],
        talon: [Card],
        declarer: PlayerID,
        contract: GameContract,
        delta: inout ScoreDelta
    ) {
        guard rules.dealerTalonCompensation == .classic,
              players.count == 4,
              !activePlayers.contains(dealer) else { return }
        let bonusTricks = dealerGameTalonTricks(talon)
        guard bonusTricks > 0 else { return }
        delta.addWhists(
            whistValue(contract) * bonusTricks,
            writer: dealer,
            on: declarer
        )
    }

    private func applyDealerMisereTalonCompensation(
        dealer: PlayerID,
        activePlayers: [PlayerID],
        talon: [Card],
        declarer: PlayerID,
        delta: inout ScoreDelta
    ) {
        guard rules.dealerTalonCompensation == .classic,
              players.count == 4,
              !activePlayers.contains(dealer) else { return }
        let bonusWhists = dealerMisereTalonWhists(talon) * rules.whistValueMultiplier
        guard bonusWhists > 0 else { return }
        delta.addWhists(bonusWhists, writer: dealer, on: declarer)
    }

    /// Two aces count as three tricks; suited ace-king as two; one ace or a
    /// suited king-queen marriage as one. Higher combinations take precedence
    /// because a two-card talon can satisfy more than one lower condition.
    private func dealerGameTalonTricks(_ talon: [Card]) -> Int {
        guard talon.count == 2 else { return 0 }
        let aceCount = talon.filter { $0.rank == .ace }.count
        if aceCount == 2 { return 3 }
        if suited(talon, ranks: [.ace, .king]) { return 2 }
        if aceCount == 1 || suited(talon, ranks: [.king, .queen]) { return 1 }
        return 0
    }

    /// Misère pays ten whists per seven. A suited seven-eight combination is
    /// conventionally valued as twenty even though it contains one seven.
    private func dealerMisereTalonWhists(_ talon: [Card]) -> Int {
        guard talon.count == 2 else { return 0 }
        if suited(talon, ranks: [.seven, .eight]) { return 20 }
        return talon.filter { $0.rank == .seven }.count * 10
    }

    private func suited(_ cards: [Card], ranks: Set<Rank>) -> Bool {
        cards.count == 2
            && cards[0].suit == cards[1].suit
            && Set(cards.map(\.rank)) == ranks
    }

    private func applyDeclarerRemiseConsolation(
        undertricks: Int,
        context: GamePlayContext,
        whistValue: Int,
        delta: inout ScoreDelta
    ) {
        guard rules.failedDeclarerConsolation == .eachDefender else { return }

        if rules.singleWhistScoring == .gentleman, context.whisters.count == 1 {
            let share = whistValue * undertricks / context.defenders.count
            for defender in context.defenders {
                delta.addWhists(share, writer: defender, on: context.declarer)
            }
            return
        }

        for defender in context.defenders {
            delta.addWhists(whistValue * undertricks, writer: defender, on: context.declarer)
        }
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

    private func openingHands(from declaration: ContractDeclarationState) -> [PlayerID: [Card]]? {
        var hands = declaration.hands
        restoreDeclarerOpeningHand(
            declarer: declaration.declarer,
            talon: declaration.talon,
            discard: declaration.discard,
            hands: &hands
        )
        return validOpeningHands(hands, activePlayers: declaration.activePlayers)
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

// MARK: - Executable rulebook examples

/// A contract row generated by the same scorer that records a real deal.
/// Keeping these values in the engine lets the in-app rulebook explain the
/// active convention without reimplementing its arithmetic in SwiftUI.
public struct ContractRuleExample: Equatable, Sendable {
    public let tricks: Int
    public let madePool: Int
    public let failedByOneMountain: Int
    public let whistPerDefenderTrick: Int

    public init(
        tricks: Int,
        madePool: Int,
        failedByOneMountain: Int,
        whistPerDefenderTrick: Int
    ) {
        self.tricks = tricks
        self.madePool = madePool
        self.failedByOneMountain = failedByOneMountain
        self.whistPerDefenderTrick = whistPerDefenderTrick
    }
}

public struct MisereRuleExample: Equatable, Sendable {
    public let madePool: Int
    public let failedOneTrickMountain: Int

    public init(madePool: Int, failedOneTrickMountain: Int) {
        self.madePool = madePool
        self.failedOneTrickMountain = failedOneTrickMountain
    }
}

public struct RaspasyRuleExample: Equatable, Sendable {
    /// One-based deal number in a consecutive raspasy series.
    public let stage: Int
    public let trickPrice: Int
    public let cleanExitPool: Int
    public let minimumGameTricks: Int
    /// Score for the fixed 0/4/6-trick example in seat order.
    public let mountainForZeroFourSix: [Int]

    public init(
        stage: Int,
        trickPrice: Int,
        cleanExitPool: Int,
        minimumGameTricks: Int,
        mountainForZeroFourSix: [Int]
    ) {
        self.stage = stage
        self.trickPrice = trickPrice
        self.cleanExitPool = cleanExitPool
        self.minimumGameTricks = minimumGameTricks
        self.mountainForZeroFourSix = mountainForZeroFourSix
    }
}

public struct PreferansRulebookExamples: Equatable, Sendable {
    public let contracts: [ContractRuleExample]
    public let misere: MisereRuleExample
    public let raspasy: [RaspasyRuleExample]

    public init(
        contracts: [ContractRuleExample],
        misere: MisereRuleExample,
        raspasy: [RaspasyRuleExample]
    ) {
        self.contracts = contracts
        self.misere = misere
        self.raspasy = raspasy
    }
}

/// Public, deterministic rule examples backed by ``PreferansScoring``.
/// They are presentation-neutral and cheap enough to construct when a rules
/// screen opens. Tests can compare them directly with real deal outcomes.
public enum PreferansRulebook {
    private static let players: [PlayerID] = ["declarer", "left", "right"]

    public static func examples(
        rules: PreferansRules,
        match: MatchSettings
    ) -> PreferansRulebookExamples {
        PreferansRulebookExamples(
            contracts: (6...10).map { contractExample(tricks: $0, rules: rules, match: match) },
            misere: misereExample(rules: rules, match: match),
            raspasy: (0...2).map { raspasyExample(precedingDeals: $0, rules: rules, match: match) }
        )
    }

    private static func contractExample(
        tricks: Int,
        rules: PreferansRules,
        match: MatchSettings
    ) -> ContractRuleExample {
        let contract = GameContract(tricks, .suit(.spades))
        let defenders = Array(players.dropFirst())
        let context = GamePlayContext(
            declarer: players[0],
            contract: contract,
            defenders: defenders,
            whisters: defenders,
            defenderPlayMode: .closed,
            whistCalls: defenders.map { WhistCallRecord(player: $0, call: .whist) }
        )
        let scoring = PreferansScoring(players: players, rules: rules, match: match)
        let made = scoring.completedPlay(playing(
            kind: .game(context),
            trickCounts: [players[0]: tricks, players[1]: 10 - tricks, players[2]: 0]
        ))
        let failed = scoring.completedPlay(playing(
            kind: .game(context),
            trickCounts: [players[0]: tricks - 1, players[1]: 11 - tricks, players[2]: 0]
        ))
        return ContractRuleExample(
            tricks: tricks,
            madePool: made.scoreDelta.pool[players[0]] ?? 0,
            failedByOneMountain: failed.scoreDelta.mountain[players[0]] ?? 0,
            whistPerDefenderTrick: contract.value * rules.whistValueMultiplier
        )
    }

    private static func misereExample(
        rules: PreferansRules,
        match: MatchSettings
    ) -> MisereRuleExample {
        let scoring = PreferansScoring(players: players, rules: rules, match: match)
        let kind = PlayKind.misere(MiserePlayContext(declarer: players[0]))
        let made = scoring.completedPlay(playing(
            kind: kind,
            trickCounts: [players[0]: 0, players[1]: 5, players[2]: 5]
        ))
        let failed = scoring.completedPlay(playing(
            kind: kind,
            trickCounts: [players[0]: 1, players[1]: 5, players[2]: 4]
        ))
        return MisereRuleExample(
            madePool: made.scoreDelta.pool[players[0]] ?? 0,
            failedOneTrickMountain: failed.scoreDelta.mountain[players[0]] ?? 0
        )
    }

    private static func raspasyExample(
        precedingDeals: Int,
        rules: PreferansRules,
        match: MatchSettings
    ) -> RaspasyRuleExample {
        let counts = [players[0]: 0, players[1]: 4, players[2]: 6]
        let scoring = PreferansScoring(
            players: players,
            rules: rules,
            match: match,
            consecutiveAllPassDeals: precedingDeals
        )
        let result = scoring.completedPlay(playing(
            kind: .allPass(AllPassPlayContext(talonPolicy: rules.allPassTalonPolicy)),
            trickCounts: counts
        ))
        let mountains = players.map { result.scoreDelta.mountain[$0] ?? 0 }
        let trickPrice = (result.scoreDelta.mountain[players[1]] ?? 0) / 4
        return RaspasyRuleExample(
            stage: precedingDeals + 1,
            trickPrice: trickPrice,
            cleanExitPool: result.scoreDelta.pool[players[0]] ?? 0,
            minimumGameTricks: match.raspasy.minimumGameTricks(after: precedingDeals),
            mountainForZeroFourSix: mountains
        )
    }

    private static func playing(
        kind: PlayKind,
        trickCounts: [PlayerID: Int]
    ) -> PlayingState {
        PlayingState(
            dealer: players[2],
            activePlayers: players,
            hands: players.dictionary(filledWith: [Card]()),
            talon: [],
            leader: players[0],
            currentPlayer: players[0],
            trickCounts: trickCounts,
            kind: kind
        )
    }
}
