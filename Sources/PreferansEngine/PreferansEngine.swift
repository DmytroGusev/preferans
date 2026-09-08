import Foundation

public struct PreferansEngine: Sendable {
    public let players: [PlayerID]
    public let rules: PreferansRules
    public let match: MatchSettings
    public private(set) var state: DealState
    public private(set) var score: ScoreSheet
    public private(set) var nextDealer: PlayerID
    public private(set) var dealsPlayed: Int
    /// Number of immediately preceding deals that ended in raspasy. This is
    /// match state, not deal state: it drives the next all-pass price and the
    /// minimum ordinary contract allowed in the next auction.
    public private(set) var consecutiveAllPassDeals: Int

    /// Whether a declared 10-trick contract goes through the ordinary
    /// whist/pass decision instead of starting as an open-card check.
    /// Either surface switches it on: the rules variant
    /// (``PreferansRules/requireWhistOnTenTrickContracts``, e.g. Wien) or the
    /// match's totus policy (``TotusPolicy``'s `requireWhist`).
    var requiresWhistOnTenTricks: Bool {
        rules.requireWhistOnTenTrickContracts || match.totus.requireWhistOnTenTricks
    }

    public init(
        players: [PlayerID],
        rules: PreferansRules = .sochi,
        match: MatchSettings = .unbounded,
        firstDealer: PlayerID? = nil
    ) throws {
        try Self.validate(players: players)
        try Self.validate(rules: rules)
        try Self.validate(match: match, playerCount: players.count)
        let dealer = firstDealer ?? players[0]
        guard players.contains(dealer) else {
            throw PreferansError.invalidPlayer(dealer)
        }
        self.players = players
        self.rules = rules
        self.match = match
        self.state = .waitingForDeal
        self.score = ScoreSheet(players: players)
        self.nextDealer = dealer
        self.dealsPlayed = 0
        self.consecutiveAllPassDeals = 0
    }

    public init(snapshot: PreferansSnapshot) throws {
        try Self.validate(players: snapshot.players)
        try Self.validate(rules: snapshot.rules)
        try Self.validate(match: snapshot.match, playerCount: snapshot.players.count)
        guard snapshot.players.contains(snapshot.nextDealer) else {
            throw PreferansError.invalidPlayer(snapshot.nextDealer)
        }
        try Self.validateInvariants(snapshot)
        self.players = snapshot.players
        self.rules = snapshot.rules
        self.match = snapshot.match
        self.state = snapshot.state
        self.score = snapshot.score
        self.nextDealer = snapshot.nextDealer
        self.dealsPlayed = snapshot.dealsPlayed
        self.consecutiveAllPassDeals = snapshot.consecutiveAllPassDeals
    }

    public var snapshot: PreferansSnapshot {
        PreferansSnapshot(
            players: players,
            rules: rules,
            match: match,
            state: state,
            score: score,
            nextDealer: nextDealer,
            dealsPlayed: dealsPlayed,
            consecutiveAllPassDeals: consecutiveAllPassDeals
        )
    }

    public var canStartDeal: Bool {
        switch state {
        case .waitingForDeal, .dealFinished:
            return true
        case .bidding, .awaitingDiscard, .awaitingContract, .awaitingWhist,
             .awaitingDefenderMode, .playing, .gameOver:
            return false
        }
    }

    @discardableResult
    public mutating func startDeal(dealer: PlayerID? = nil, deck: [Card]? = nil) throws -> [PreferansEvent] {
        try apply(.startDeal(dealer: dealer, deck: deck))
    }

    public mutating func apply(_ action: PreferansAction) throws -> [PreferansEvent] {
        let events = try dispatch(action)
        assertInvariants()
        return events
    }

    /// Private simulations start from a validated snapshot and use the same
    /// legal-move reducer. Replaying the complete history after every simulated
    /// card makes Debug bot matches spend most of their time in assertions.
    mutating func applyRolloutCard(player: PlayerID, card: Card) throws {
        _ = try dispatch(.playCard(player: player, card: card))
    }

    private mutating func dispatch(_ action: PreferansAction) throws -> [PreferansEvent] {
        let transition = try reduce(action)
        state = transition.state
        return transition.events
    }

    private mutating func reduce(_ action: PreferansAction) throws -> EngineTransition {
        switch action {
        case let .startDeal(dealer, deck):
            return try reduceStartDeal(dealer: dealer, deck: deck)
        case let .bid(player, call):
            return try reduceBid(player: player, call: call)
        case let .discard(player, cards):
            return try reduceDiscard(player: player, cards: cards)
        case let .declareContract(player, contract):
            return try reduceDeclareContract(player: player, contract: contract)
        case let .concedeWithoutThree(player):
            return try reduceConcedeWithoutThree(player: player)
        case let .whist(player, call):
            return try reduceWhist(player: player, call: call)
        case let .chooseDefenderMode(player, mode):
            return try reduceChooseDefenderMode(player: player, mode: mode)
        case let .playCard(player, card):
            return try reducePlayCard(player: player, card: card)
        case let .proposeSettlement(player, settlement):
            return try reduceProposeSettlement(player: player, settlement: settlement)
        case let .acceptSettlement(player):
            return try reduceAcceptSettlement(player: player)
        case let .rejectSettlement(player):
            return try reduceRejectSettlement(player: player)
        }
    }

    public func legalBidCalls(for player: PlayerID) -> [BidCall] {
        guard case let .bidding(bidding) = state, bidding.currentPlayer == player else {
            return []
        }

        var calls: [BidCall] = [.pass]
        for bid in ContractBid.allStandard where isLegalBid(bid, by: player, in: bidding) {
            calls.append(.bid(bid))
        }
        return calls
    }

    public func legalWhistCalls(for player: PlayerID) -> [WhistCall] {
        guard case let .awaitingWhist(whist) = state, whist.currentPlayer == player else {
            return []
        }
        return legalWhistCalls(in: whist, for: player)
    }

    public func legalCards(for player: PlayerID) -> [Card] {
        guard case let .playing(playing) = state,
              playing.pendingSettlement == nil else {
            return []
        }
        let current = playing.currentPlayer
        let controller = playing.controllingActor(of: current, rules: rules)
        guard player == controller else { return [] }
        return (playing.hands[current] ?? []).filter { isLegal(card: $0, by: current, in: playing) }
    }

    /// Resolves the seat authorized to send actions for `player`. When a
    /// passer's turn comes up in an open single-whist greedy game, the lone
    /// whister speaks for them; otherwise the seat speaks for itself.
    /// Used by the host actor (sender validation), the bot dispatcher
    /// (deciding when to act for another seat), and the projection (who
    /// gets the playable-cards affordance).
    public func controllingActor(of player: PlayerID) -> PlayerID {
        guard case let .playing(playing) = state else { return player }
        return playing.controllingActor(of: player, rules: rules)
    }

    /// Seat being controlled by `player` right now, or `nil` when `player`
    /// only speaks for themselves. The inverse of ``controllingActor(of:)``
    /// at the seat that's currently up — useful for UI affordances and
    /// bot decisions ("am I the controller of the current actor?").
    public func controlledSeat(by player: PlayerID) -> PlayerID? {
        guard case let .playing(playing) = state else { return nil }
        let current = playing.currentPlayer
        let controller = playing.controllingActor(of: current, rules: rules)
        guard controller == player, controller != current else { return nil }
        return current
    }

    /// Settlement offers `player` may legally propose right now. A
    /// settlement ends play early by agreeing on the final trick split, so
    /// only a side that plays with its cards exposed may offer one: the
    /// declarer or a whister during an *open* game, or anyone during a
    /// misère. A closed game and an all-pass deal are always played out,
    /// and a defender who merely passed (never whisted) cannot offer.
    /// Returns `[]` when `player` is not entitled to settle the current
    /// position. See ``eligibleSettlementProposers(in:)``.
    public func legalSettlements(for player: PlayerID) -> [TrickSettlement] {
        guard case let .playing(playing) = state,
              playing.pendingSettlement == nil,
              playing.currentTrick.isEmpty,
              !playing.isComplete,
              eligibleSettlementProposers(in: playing).contains(player) else {
            return []
        }

        return candidateSettlements(in: playing, knownTo: player)
    }

    /// Seats permitted to *offer* a settlement in the current position.
    /// Only sides whose cards are on the table may settle:
    /// - **Open game** — the declarer and the whisters (a passed-out
    ///   defender is excluded).
    /// - **Misère** — the declarer and every defender (a misère has no
    ///   whist phase, so all defenders qualify).
    /// - **Closed game / all-pass** — nobody; the deal is played out.
    func eligibleSettlementProposers(in playing: PlayingState) -> Set<PlayerID> {
        playing.settlementParties
    }

    /// The canonical anchor offers for the current position: concede every
    /// remaining trick to the defence, claim them all for the declarer, and —
    /// when the rest of the play is forced — the determined split. These are
    /// the meaningful endpoints. The UI's tug-of-war composer lets a proposer
    /// pick any split *between* them, and the reducer accepts any
    /// ``validateSettlement(_:in:)``-valid configuration, so the engine never
    /// has to enumerate the continuum. A non-empty result here also gates
    /// whether a seat may settle at all. Duplicates are collapsed (e.g. with
    /// one trick left, or when the forced split matches a concession).
    private func candidateSettlements(in playing: PlayingState, knownTo viewer: PlayerID) -> [TrickSettlement] {
        let declarer: PlayerID
        switch playing.kind {
        case let .game(context):   declarer = context.declarer
        case let .misere(context): declarer = context.declarer
        case .allPass:             return []
        }
        let remaining = 10 - playing.completedTricks.count
        guard remaining > 0 else { return [] }
        let defenders = playing.activePlayers.filter { $0 != declarer }

        var offers: [TrickSettlement] = [
            settlementGivingDeclarer(0, declarer: declarer, defenders: defenders, in: playing),
            settlementGivingDeclarer(remaining, declarer: declarer, defenders: defenders, in: playing),
        ]
        if let forced = forcedSettlement(in: playing, knownTo: viewer) {
            offers.append(forced)
        }

        var unique: [TrickSettlement] = []
        for offer in offers where !unique.contains(offer) {
            unique.append(offer)
        }
        return unique
    }

    /// Builds a settlement that credits the declarer with `declarerExtra`
    /// of the remaining tricks and spreads the rest across the defenders in
    /// seat order. The result always totals ten and never takes back a
    /// trick already won, so it satisfies ``validateSettlement(_:in:)``.
    private func settlementGivingDeclarer(
        _ declarerExtra: Int,
        declarer: PlayerID,
        defenders: [PlayerID],
        in playing: PlayingState
    ) -> TrickSettlement {
        var counts = playing.trickCounts
        counts[declarer, default: 0] += declarerExtra
        var defenseRemaining = (10 - playing.completedTricks.count) - declarerExtra
        var index = 0
        while defenseRemaining > 0, !defenders.isEmpty {
            let defender = defenders[index % defenders.count]
            counts[defender, default: 0] += 1
            defenseRemaining -= 1
            index += 1
        }
        return TrickSettlement(
            target: declarer,
            targetTricks: counts[declarer] ?? 0,
            finalTrickCounts: counts
        )
    }

    public func canAcceptSettlement(player: PlayerID) -> Bool {
        guard case let .playing(playing) = state,
              let proposal = playing.pendingSettlement,
              playing.settlementParties.contains(player) else {
            return false
        }
        return !proposal.acceptedBy.contains(player)
    }

    public func canRejectSettlement(player: PlayerID) -> Bool {
        guard case let .playing(playing) = state,
              playing.pendingSettlement != nil else {
            return false
        }
        return playing.settlementParties.contains(player)
    }

    /// Contracts the declarer may legally declare in ``DealState/awaitingContract``.
    /// For a totus auction the list is constrained to 10-trick contracts only;
    /// for a normal game auction the list is the standard ladder above the
    /// auction-winning bid.
    public func legalContractDeclarations(for player: PlayerID) -> [GameContract] {
        guard case let .awaitingContract(declaration) = state,
              declaration.declarer == player else {
            return []
        }
        switch declaration.finalBid {
        case .totus:
            return Strain.allStandard.map { GameContract(10, $0) }
        case let .game(finalGameBid):
            return GameContract.allStandard.filter { $0 >= finalGameBid }
        case .misere:
            return []
        }
    }

    private var scoring: PreferansScoring {
        PreferansScoring(
            players: players,
            rules: rules,
            match: match,
            consecutiveAllPassDeals: consecutiveAllPassDeals
        )
    }

    private static func validate(players: [PlayerID]) throws {
        guard players.count == 3 || players.count == 4 else {
            throw PreferansError.invalidPlayers("PreferansEngine requires exactly 3 or 4 players.")
        }
        guard Set(players).count == players.count else {
            throw PreferansError.invalidPlayers("PlayerID values must be unique.")
        }
    }

    private static func validate(rules: PreferansRules) throws {
        if let message = rules.configurationError {
            throw PreferansError.invalidRules(message)
        }
    }

    private static func validate(match: MatchSettings, playerCount: Int) throws {
        if let error = match.configurationError(playerCount: playerCount) {
            throw PreferansError.invalidMatch(error)
        }
    }

    private mutating func reduceStartDeal(dealer suppliedDealer: PlayerID?, deck suppliedDeck: [Card]?) throws -> EngineTransition {
        switch state {
        case .waitingForDeal, .dealFinished:
            break
        case .gameOver:
            throw PreferansError.invalidState(expected: "waitingForDeal or dealFinished", actual: "gameOver (match closed)")
        default:
            throw PreferansError.invalidState(expected: "waitingForDeal or dealFinished", actual: state.description)
        }

        let dealer = suppliedDealer ?? nextDealer
        guard players.contains(dealer) else {
            throw PreferansError.invalidPlayer(dealer)
        }

        let activePlayers = activePlayers(forDealer: dealer)
        let deck = try preparedDeck(suppliedDeck)
        let deal = dealHands(deck: deck, activePlayers: activePlayers)

        nextDealer = players.cyclicNext(after: dealer)
        let nextState = DealState.bidding(
            BiddingState(
                dealer: dealer,
                activePlayers: activePlayers,
                hands: deal.hands,
                talon: deal.talon,
                currentPlayer: activePlayers[0]
            )
        )

        return EngineTransition(state: nextState, events: [.dealStarted(dealer: dealer, activePlayers: activePlayers)])
    }

    func validateCurrent(_ actual: PlayerID, expected: PlayerID) throws {
        guard actual == expected else {
            throw PreferansError.notPlayersTurn(expected: expected, actual: actual)
        }
    }

    func isLegalBid(_ bid: ContractBid, by player: PlayerID, in bidding: BiddingState) -> Bool {
        guard bidding.currentPlayer == player, !bidding.passed.contains(player) else {
            return false
        }

        // Totus is only a real bid when the match opts into the dedicated
        // contract; otherwise the 10-trick contracts in the standard ladder
        // cover the same trick count without the bonus.
        switch bid {
        case .totus where !match.totus.isDedicated:
            return false
        case let .game(contract) where contract.tricks == 10 && match.totus.isDedicated:
            // In dedicated-totus matches the 10-trick bid moves to .totus, so
            // the standard 10-trick game contracts are removed from the ladder
            // to avoid two parallel paths to the same outcome.
            return false
        default:
            break
        }

        if case let .game(contract) = bid,
           contract.tricks < match.raspasy.minimumGameTricks(after: consecutiveAllPassDeals) {
            return false
        }

        if bid == .misere {
            guard bidding.significantBidByPlayer[player] == nil else { return false }
        } else if bidding.significantBidByPlayer[player] == .misere {
            return false
        }

        guard let highest = bidding.highestBid else {
            return true
        }

        if bid > highest {
            return true
        }

        guard rules.allowSeniorHandHoldBid,
              bid == highest,
              case .game = bid,
              bidding.activePlayers.filter({ !bidding.passed.contains($0) }).count == 2,
              let highestBidder = bidding.highestBidder
        else {
            return false
        }

        return isOlderHand(player, than: highestBidder, activePlayers: bidding.activePlayers)
    }

    func legalWhistCalls(in whist: WhistState, for player: PlayerID) -> [WhistCall] {
        guard whist.defenders.contains(player), whist.currentPlayer == player else {
            return []
        }
        if isStalingradContract(whist.contract) {
            return [.whist]
        }
        switch whist.flow {
        case .firstDefenderSecondChance:
            return [.pass, .whist]
        case .normal:
            let first = whist.defenders[0]
            let firstCall = whist.calls.first { $0.player == first }?.call
            if player == first {
                return [.pass, .whist]
            }
            if firstCall == .pass && whist.contract.tricks <= 7 {
                return [.pass, .halfWhist, .whist]
            }
            return [.pass, .whist]
        }
    }

    private func isStalingradContract(_ contract: GameContract) -> Bool {
        rules.forceWhistOnSixSpades
            && contract == GameContract(6, .suit(.spades))
    }

    /// Active rotation for a deal with the given dealer. In 3-player matches
    /// every seat is active and the rotation starts immediately after the
    /// dealer; in 4-player matches the dealer sits out and the next three
    /// seats fill the rotation. Exposed publicly so test harnesses and UI
    /// fixtures can pre-compute the rotation before calling ``startDeal``.
    public func activePlayers(forDealer dealer: PlayerID) -> [PlayerID] {
        guard let dealerIndex = players.firstIndex(of: dealer) else { return [] }
        let rotated = Array(players[(dealerIndex + 1)...]) + Array(players[..<dealerIndex])
        // 3-player tables fold the dealer back at the end of the rotation;
        // 4-player tables let the dealer sit the deal out.
        return players.count == 3 ? rotated + [dealer] : rotated
    }

    func nextBidder(after player: PlayerID, in bidding: BiddingState) -> PlayerID? {
        guard let index = bidding.activePlayers.firstIndex(of: player) else { return nil }
        for offset in 1...bidding.activePlayers.count {
            let candidate = bidding.activePlayers[(index + offset) % bidding.activePlayers.count]
            if !bidding.passed.contains(candidate) {
                return candidate
            }
        }
        return nil
    }

    func defenders(after declarer: PlayerID, activePlayers: [PlayerID]) -> [PlayerID] {
        var defenders: [PlayerID] = []
        var current = activePlayers.cyclicNext(after: declarer)
        while current != declarer {
            defenders.append(current)
            current = activePlayers.cyclicNext(after: current)
        }
        return defenders
    }

    private func isOlderHand(_ lhs: PlayerID, than rhs: PlayerID, activePlayers: [PlayerID]) -> Bool {
        guard let lhsIndex = activePlayers.firstIndex(of: lhs),
              let rhsIndex = activePlayers.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }

    private func preparedDeck(_ suppliedDeck: [Card]?) throws -> [Card] {
        let deck = suppliedDeck ?? Deck.standard32.shuffled()
        guard deck.count == Deck.standard32.count else {
            throw PreferansError.invalidDeck("Deck must contain 32 cards.")
        }
        let duplicates = duplicateCards(in: deck)
        guard duplicates.isEmpty else {
            throw PreferansError.duplicateCards(duplicates)
        }
        guard Set(deck) == Set(Deck.standard32) else {
            throw PreferansError.invalidDeck("Deck must contain the standard Preferans cards.")
        }
        return deck
    }

    private func duplicateCards(in cards: [Card]) -> [Card] {
        var seen: Set<Card> = []
        var duplicates: Set<Card> = []
        for card in cards {
            if seen.contains(card) {
                duplicates.insert(card)
            } else {
                seen.insert(card)
            }
        }
        return duplicates.sorted()
    }

    private func dealHands(deck: [Card], activePlayers: [PlayerID]) -> (hands: [PlayerID: [Card]], talon: [Card]) {
        let deal = DealDeckLayout.deal(deck: deck, activePlayers: activePlayers)
        return (deal.hands, deal.talon)
    }

    func makePlayingState(
        dealer: PlayerID,
        activePlayers: [PlayerID],
        hands: [PlayerID: [Card]],
        talon: [Card],
        discard: [Card],
        kind: PlayKind
    ) -> PlayingState {
        let dealerLeads = !activePlayers.contains(dealer)
            && {
                guard case let .allPass(context) = kind else { return false }
                return context.talonPolicy == .classic
            }()
        return PlayingState(
            dealer: dealer,
            activePlayers: activePlayers,
            hands: hands,
            talon: talon,
            discard: discard,
            leader: dealerLeads ? dealer : activePlayers[0],
            currentPlayer: activePlayers[0],
            kind: kind
        )
    }

    func makeDefenderModeState(whist: WhistState, whister: PlayerID) -> DefenderModeState {
        DefenderModeState(
            dealer: whist.dealer,
            activePlayers: whist.activePlayers,
            hands: whist.hands,
            talon: whist.talon,
            discard: whist.discard,
            declarer: whist.declarer,
            contract: whist.contract,
            defenders: whist.defenders,
            whister: whister,
            whistCalls: whist.calls,
            bonusPoolOnSuccess: whist.bonusPoolOnSuccess
        )
    }

    /// A forced result the viewer can establish from their own cards and
    /// public information. At an empty trick before the last, the leader has
    /// multiple legal cards, so this exact proof makes no earlier suggestion.
    func forcedSettlement(in playing: PlayingState, knownTo viewer: PlayerID) -> TrickSettlement? {
        guard playing.currentTrick.isEmpty,
              playing.completedTricks.count == 9,
              playing.settlementParties.contains(viewer) else { return nil }

        let declarer: PlayerID
        switch playing.kind {
        case let .game(context):
            if context.contract.tricks == 10 && context.whisters.isEmpty && context.whistCalls.isEmpty {
                return forcedSettlement(in: playing)
            }
            declarer = context.declarer
        case let .misere(context): declarer = context.declarer
        case .allPass: return nil
        }
        // Settlement-eligible defenders have their cards exposed. The
        // declarer therefore knows every remaining hand and their own discard.
        if viewer == declarer { return forcedSettlement(in: playing) }

        // A defender sees both defending hands but cannot distinguish the
        // declarer's last card from the two discarded cards. Check every
        // possible allocation, retaining only those consistent with the full
        // public play history. Never consult which allocation really occurred.
        var unknown = Set(Deck.standard32)
        unknown.subtract(playing.completedTricks.flatMap(\.plays).map(\.card))
        for defender in playing.activePlayers where defender != declarer {
            unknown.subtract(playing.hands[defender] ?? [])
        }
        guard unknown.count == 3 else { return nil }

        var sharedResult: TrickSettlement?
        for card in unknown.sorted() {
            var candidate = playing
            candidate.hands[declarer] = [card]
            candidate.discard = unknown.filter { $0 != card }.sorted()
            do { try Self.validateInvariants(.playing(candidate)) }
            catch { continue }
            guard let result = forcedSettlement(in: candidate) else { return nil }
            if let sharedResult, sharedResult != result { return nil }
            sharedResult = result
        }
        return sharedResult
    }

    /// Exact outcome with access to every hand. Player-facing suggestions and
    /// bot approvals must use the `knownTo:` overload instead.
    func forcedSettlement(in playing: PlayingState) -> TrickSettlement? {
        guard playing.currentTrick.isEmpty, !playing.isComplete else { return nil }
        var simulated = playing
        while !simulated.isComplete {
            let legal = (simulated.hands[simulated.currentPlayer] ?? [])
                .filter { isLegal(card: $0, by: simulated.currentPlayer, in: simulated) }
            guard legal.count == 1, let card = legal.first else { return nil }
            playForced(card, in: &simulated)
        }
        return makeSettlement(finalTrickCounts: simulated.trickCounts, in: playing)
    }

    private func playForced(_ card: Card, in playing: inout PlayingState) {
        let player = playing.currentPlayer
        guard let cardIndex = playing.hands[player]?.firstIndex(of: card) else { return }
        playing.hands[player]?.remove(at: cardIndex)
        playing.currentTrick.append(CardPlay(player: player, card: card))

        if playing.currentTrick.count < playing.activePlayers.count {
            playing.currentPlayer = playing.activePlayers.cyclicNext(after: player)
            return
        }

        _ = completeCurrentTrick(in: &playing)
    }

    private func makeSettlement(
        finalTrickCounts: [PlayerID: Int],
        in playing: PlayingState
    ) -> TrickSettlement? {
        let active = Set(playing.activePlayers)
        guard Set(finalTrickCounts.keys) == active,
              finalTrickCounts.values.reduce(0, +) == 10 else {
            return nil
        }
        for player in playing.activePlayers {
            guard let final = finalTrickCounts[player],
                  final >= Self.tricks(player, in: playing.trickCounts) else {
                return nil
            }
        }
        let target = settlementTarget(in: playing, finalTrickCounts: finalTrickCounts)
        return TrickSettlement(
            target: target,
            targetTricks: finalTrickCounts[target] ?? 0,
            finalTrickCounts: finalTrickCounts
        )
    }

    private func settlementTarget(
        in playing: PlayingState,
        finalTrickCounts: [PlayerID: Int]
    ) -> PlayerID {
        switch playing.kind {
        case let .game(context):
            return context.declarer
        case let .misere(context):
            return context.declarer
        case .allPass:
            return playing.activePlayers.max { lhs, rhs in
                let left = finalTrickCounts[lhs] ?? 0
                let right = finalTrickCounts[rhs] ?? 0
                if left != right { return left < right }
                let leftIndex = playing.activePlayers.firstIndex(of: lhs) ?? 0
                let rightIndex = playing.activePlayers.firstIndex(of: rhs) ?? 0
                return leftIndex > rightIndex
            } ?? playing.activePlayers[0]
        }
    }

    func validateSettlement(_ settlement: TrickSettlement, in playing: PlayingState) throws {
        let active = Set(playing.activePlayers)
        guard active.contains(settlement.target) else {
            throw PreferansError.illegalSettlement("Settlement target is not active in this deal.")
        }
        guard Set(settlement.finalTrickCounts.keys) == active else {
            throw PreferansError.illegalSettlement("Settlement must include final trick counts for every active player.")
        }
        guard settlement.finalTrickCounts[settlement.target] == settlement.targetTricks else {
            throw PreferansError.illegalSettlement("Settlement target count does not match final trick counts.")
        }
        let total = settlement.finalTrickCounts.values.reduce(0, +)
        guard total == 10 else {
            throw PreferansError.illegalSettlement("Settlement final trick counts must total 10.")
        }
        for player in playing.activePlayers {
            let current = Self.tricks(player, in: playing.trickCounts)
            guard let final = settlement.finalTrickCounts[player],
                  (current...10).contains(final) else {
                throw PreferansError.illegalSettlement("Settlement cannot remove tricks already won.")
            }
        }
    }

    func startGamePlay(
        from whist: WhistState,
        whisters: [PlayerID],
        mode: DefenderPlayMode
    ) -> PlayingState {
        let playing = makePlayingState(
            dealer: whist.dealer,
            activePlayers: whist.activePlayers,
            hands: whist.hands,
            talon: whist.talon,
            discard: whist.discard,
            kind: .game(
                GamePlayContext(
                    declarer: whist.declarer,
                    contract: whist.contract,
                    defenders: whist.defenders,
                    whisters: whisters,
                    defenderPlayMode: mode,
                    whistCalls: whist.calls,
                    bonusPoolOnSuccess: whist.bonusPoolOnSuccess
                )
            )
        )
        return playing
    }

    mutating func scorePassedOut(_ whist: WhistState) -> EngineTransition {
        finalize(scoring.passedOut(whist))
    }

    mutating func scoreHalfWhist(_ whist: WhistState, halfWhister: PlayerID) -> EngineTransition {
        finalize(scoring.halfWhist(whist, halfWhister: halfWhister))
    }

    mutating func scoreWithoutThree(_ declaration: ContractDeclarationState) -> EngineTransition {
        finalize(scoring.withoutThree(declaration))
    }

    /// Applies the deal's score delta, increments the deal counter, and
    /// transitions to ``DealState/gameOver`` when the match's pool-closing
    /// policy is satisfied. Otherwise transitions to ``DealState/dealFinished``.
    /// Returns the events the caller should append (always `dealScored`,
    /// optionally followed by `matchEnded`).
    mutating func finalize(_ result: DealResult) -> EngineTransition {
        let appliedDelta = score.apply(
            result.scoreDelta,
            closingAtPoolTarget: match.poolTarget,
            poolClosure: match.poolClosure,
            poolPointWhistValue: rules.poolPointWhistValue
        )
        let result = result.replacingScoreDelta(appliedDelta)
        dealsPlayed += 1
        if case .allPass = result.kind {
            if consecutiveAllPassDeals < Int.max {
                consecutiveAllPassDeals += 1
            }
        } else {
            consecutiveAllPassDeals = 0
        }
        var events: [PreferansEvent] = [.dealScored(result)]
        if match.isPoolClosed(score) {
            let summary = makeMatchSummary(lastDeal: result)
            events.append(.matchEnded(summary))
            return EngineTransition(state: .gameOver(summary), events: events)
        }
        return EngineTransition(state: .dealFinished(result), events: events)
    }

    private func makeMatchSummary(lastDeal: DealResult) -> MatchSummary {
        let balances = score.normalizedBalances(
            poolPointValue: Double(rules.poolPointWhistValue),
            mountainPointValue: Double(rules.mountainPointWhistValue)
        )
        let standings = players
            .map { player -> MatchSummary.Standing in
                MatchSummary.Standing(
                    player: player,
                    balance: balances[player] ?? 0,
                    pool: score.pool[player] ?? 0,
                    mountain: score.mountain[player] ?? 0
                )
            }
            .sorted { lhs, rhs in
                if lhs.balance != rhs.balance { return lhs.balance > rhs.balance }
                // Stable, deterministic tiebreak — seat order in `players`.
                guard let lhsIndex = players.firstIndex(of: lhs.player),
                      let rhsIndex = players.firstIndex(of: rhs.player) else {
                    return false
                }
                return lhsIndex < rhsIndex
            }
        return MatchSummary(
            finalScore: score,
            dealsPlayed: dealsPlayed,
            lastDeal: lastDeal,
            standings: standings
        )
    }

    func requiredSuit(for playing: PlayingState) -> Suit? {
        playing.requiredSuit
    }

    /// Completes one fully played trick and advances to the correct leader.
    /// The first two classic four-player raspasy tricks include a dealer-owned
    /// talon card. Every talon-led variant resets the responding order to
    /// forehand for both opening tricks and for the ordinary third lead.
    @discardableResult
    func completeCurrentTrick(in playing: inout PlayingState) -> Trick {
        precondition(playing.currentTrick.count == playing.activePlayers.count)
        let talonLead = playing.currentTalonLead
        let leadSuit = requiredSuit(for: playing) ?? playing.currentTrick[0].card.suit
        let candidates = (talonLead.map { [$0] } ?? []) + playing.currentTrick
        let winner = trickWinner(
            for: candidates,
            leadSuit: leadSuit,
            trump: playing.kind.trumpSuit
        )
        let trick = Trick(
            leader: talonLead?.player ?? playing.leader,
            leadSuit: leadSuit,
            talonLead: talonLead,
            plays: playing.currentTrick,
            winner: winner
        )
        playing.completedTricks.append(trick)
        playing.trickCounts[winner, default: 0] += 1
        playing.currentTrick = []

        if playing.usesTalonLeads, playing.completedTricks.count <= 2 {
            playing.currentPlayer = playing.activePlayers[0]
            playing.leader = playing.isClassicFourPlayerAllPass
                && playing.completedTricks.count < 2
                ? playing.dealer
                : playing.activePlayers[0]
        } else {
            playing.currentPlayer = winner
            playing.leader = winner
        }
        return trick
    }

    func isLegal(card: Card, by player: PlayerID, in playing: PlayingState) -> Bool {
        guard let hand = playing.hands[player], hand.contains(card) else {
            return false
        }

        guard let requiredSuit = requiredSuit(for: playing) else {
            return true
        }

        if hand.contains(where: { $0.suit == requiredSuit }) {
            return card.suit == requiredSuit
        }

        if let trump = playing.kind.trumpSuit, requiredSuit != trump, hand.contains(where: { $0.suit == trump }) {
            return card.suit == trump
        }

        return true
    }

    func trickWinner(for trick: [CardPlay], leadSuit: Suit, trump: Suit?) -> PlayerID {
        Self.trickWinner(for: trick, leadSuit: leadSuit, trump: trump).player
    }

    /// Picks the winning play of a (possibly partial) trick using standard
    /// preferans precedence (trump > lead-suit > off-suit). Crashes if the
    /// trick is empty — callers must check before invoking.
    static func trickWinner(for trick: [CardPlay], leadSuit: Suit, trump: Suit?) -> CardPlay {
        trick.max { lhs, rhs in
            compare(lhs.card, rhs.card, leadSuit: leadSuit, trump: trump) == .orderedAscending
        }!
    }

    /// Trick-context ordering: same-suit cards compare by rank; trump beats
    /// non-trump; lead suit beats off-suit-non-trump; everything else is
    /// `.orderedSame` (cards that can't beat each other in this trick).
    static func compare(_ left: Card, _ right: Card, leadSuit: Suit, trump: Suit?) -> ComparisonResult {
        if left.suit == right.suit {
            if left.rank == right.rank { return .orderedSame }
            return left.rank < right.rank ? .orderedAscending : .orderedDescending
        }
        if let trump {
            if left.suit == trump { return .orderedDescending }
            if right.suit == trump { return .orderedAscending }
        }
        if left.suit == leadSuit { return .orderedDescending }
        if right.suit == leadSuit { return .orderedAscending }
        return .orderedSame
    }

    func scoreSettlement(_ settlement: TrickSettlement, in playing: PlayingState) throws -> DealResult {
        try validateSettlement(settlement, in: playing)
        var settled = playing
        settled.trickCounts = settlement.finalTrickCounts
        settled.currentTrick = []
        settled.pendingSettlement = nil
        return scoring.completedPlay(settled, settlement: settlement)
    }

    func scoreCompletedPlay(_ playing: PlayingState, settlement: TrickSettlement? = nil) -> DealResult {
        scoring.completedPlay(playing, settlement: settlement)
    }

    /// Static helper that resolves a player's trick count from a guaranteed-
    /// non-nil dictionary. A nil read is an engine bug, not a recoverable case.
    fileprivate static func tricks(_ player: PlayerID, in trickCounts: [PlayerID: Int]) -> Int {
        guard let count = trickCounts[player] else {
            preconditionFailure("trickCounts missing entry for \(player) — invariant violated")
        }
        return count
    }

}
