import Foundation

public struct PreferansEngine: Sendable {
    public let players: [PlayerID]
    public let rules: PreferansRules
    public let match: MatchSettings
    public private(set) var state: DealState
    public private(set) var score: ScoreSheet
    public private(set) var nextDealer: PlayerID
    public private(set) var dealsPlayed: Int

    public init(
        players: [PlayerID],
        rules: PreferansRules = .sochi,
        match: MatchSettings = .unbounded,
        firstDealer: PlayerID? = nil
    ) throws {
        try Self.validate(players: players)
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
    }

    public init(snapshot: PreferansSnapshot) throws {
        try Self.validate(players: snapshot.players)
        guard snapshot.players.contains(snapshot.nextDealer) else {
            throw PreferansError.invalidPlayer(snapshot.nextDealer)
        }
        self.players = snapshot.players
        self.rules = snapshot.rules
        self.match = snapshot.match
        self.state = snapshot.state
        self.score = snapshot.score
        self.nextDealer = snapshot.nextDealer
        self.dealsPlayed = snapshot.dealsPlayed
        assertInvariants()
    }

    public var snapshot: PreferansSnapshot {
        PreferansSnapshot(
            players: players,
            rules: rules,
            match: match,
            state: state,
            score: score,
            nextDealer: nextDealer,
            dealsPlayed: dealsPlayed
        )
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
              playing.pendingSettlement == nil,
              playing.currentPlayer == player else {
            return []
        }
        return (playing.hands[player] ?? []).filter { isLegal(card: $0, by: player, in: playing) }
    }

    public func legalSettlements(for player: PlayerID) -> [TrickSettlement] {
        guard case let .playing(playing) = state,
              playing.pendingSettlement == nil,
              playing.currentTrick.isEmpty,
              playing.activePlayers.contains(player) else {
            return []
        }

        var settlements: [TrickSettlement] = []
        for target in playing.activePlayers {
            let current = Self.tricks(target, in: playing.trickCounts)
            let remaining = 10 - playing.completedTricks.count
            for targetTricks in current...(current + remaining) {
                if let settlement = makeSettlement(target: target, targetTricks: targetTricks, in: playing) {
                    settlements.append(settlement)
                }
            }
        }
        return settlements
    }

    public func canAcceptSettlement(player: PlayerID) -> Bool {
        guard case let .playing(playing) = state,
              let proposal = playing.pendingSettlement,
              playing.activePlayers.contains(player) else {
            return false
        }
        return !proposal.acceptedBy.contains(player)
    }

    public func canRejectSettlement(player: PlayerID) -> Bool {
        guard case let .playing(playing) = state,
              playing.pendingSettlement != nil else {
            return false
        }
        return playing.activePlayers.contains(player)
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
        PreferansScoring(players: players, rules: rules, match: match)
    }

    private static func validate(players: [PlayerID]) throws {
        guard players.count == 3 || players.count == 4 else {
            throw PreferansError.invalidPlayers("PreferansEngine requires exactly 3 or 4 players.")
        }
        guard Set(players).count == players.count else {
            throw PreferansError.invalidPlayers("PlayerID values must be unique.")
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
        contract == GameContract(6, .suit(.spades))
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
        PlayingState(
            dealer: dealer,
            activePlayers: activePlayers,
            hands: hands,
            talon: talon,
            discard: discard,
            leader: activePlayers[0],
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

    private func makeSettlement(
        target: PlayerID,
        targetTricks: Int,
        in playing: PlayingState
    ) -> TrickSettlement? {
        guard playing.activePlayers.contains(target),
              targetTricks >= Self.tricks(target, in: playing.trickCounts) else {
            return nil
        }

        var counts = playing.trickCounts
        counts[target] = targetTricks
        var remaining = 10 - counts.values.reduce(0, +)
        guard remaining >= 0 else { return nil }

        // The action itself accepts any valid complete trick-count map.
        // This helper is only for compact UI/bot-generated "X takes N"
        // offers, so it fills the non-target remainder deterministically.
        for player in playing.activePlayers where player != target && remaining > 0 {
            let capacity = 10 - (counts[player] ?? 0)
            let assigned = min(capacity, remaining)
            counts[player, default: 0] += assigned
            remaining -= assigned
        }
        guard remaining == 0 else { return nil }

        return TrickSettlement(
            target: target,
            targetTricks: targetTricks,
            finalTrickCounts: counts
        )
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

    /// Applies the deal's score delta, increments the deal counter, and
    /// transitions to ``DealState/gameOver`` when the pool sum has reached the
    /// match's pool target. Otherwise transitions to ``DealState/dealFinished``.
    /// Returns the events the caller should append (always `dealScored`,
    /// optionally followed by `matchEnded`).
    mutating func finalize(_ result: DealResult) -> EngineTransition {
        score.apply(result.scoreDelta)
        dealsPlayed += 1
        var events: [PreferansEvent] = [.dealScored(result)]
        let totalPool = score.pool.values.reduce(0, +)
        if totalPool >= match.poolTarget {
            let summary = makeMatchSummary(lastDeal: result)
            events.append(.matchEnded(summary))
            return EngineTransition(state: .gameOver(summary), events: events)
        }
        return EngineTransition(state: .dealFinished(result), events: events)
    }

    private func makeMatchSummary(lastDeal: DealResult) -> MatchSummary {
        let balances = score.normalizedBalances()
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
        if let lead = playing.currentTrick.first?.card.suit {
            return lead
        }
        guard case let .allPass(context) = playing.kind,
              context.talonPolicy == .leadSuitOnly,
              playing.completedTricks.count < 2,
              playing.talon.indices.contains(playing.completedTricks.count) else {
            return nil
        }
        return playing.talon[playing.completedTricks.count].suit
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

    /// Postcondition check called after every successful `apply(_:)` and on
    /// snapshot rehydration. Delegates to ``validateInvariants(_:)`` and
    /// traps via `precondition` on violation — these are engine-internal
    /// bugs, not recoverable input errors. The throwing validator exists so
    /// tests can verify each invariant fires without crashing the process.
    /// Adding new state arms or new mutators? Add the matching invariant in
    /// ``validateInvariants(_:)``.
    private func assertInvariants(file: StaticString = #file, line: UInt = #line) {
        do {
            try Self.validateInvariants(snapshot)
        } catch let violation as InvariantViolation {
            preconditionFailure(violation.message, file: file, line: line)
        } catch {
            preconditionFailure("unexpected error during invariant check: \(error)", file: file, line: line)
        }
    }

    /// Throws ``InvariantViolation`` if `state` violates any structural
    /// invariant that mutators are responsible for maintaining (seat counts,
    /// hand keys, hand sizes, trick-count keys, discard size, current/leader
    /// membership). Used by both ``assertInvariants()`` (which traps) and the
    /// invariant tests (which assert the throw).
    static func validateInvariants(_ state: DealState) throws {
        switch state {
        case .waitingForDeal:
            return
        case let .dealFinished(result):
            try checkResult(result, context: "dealFinished")
        case let .gameOver(summary):
            try checkResult(summary.lastDeal, context: "gameOver lastDeal")
        case let .bidding(s):
            try checkActiveSeats(s.activePlayers)
            try checkHands(s.hands, seats: s.activePlayers, expected: 10)
            try require(s.talon.count == 2, "bidding talon must be 2 cards, got \(s.talon.count)")
            try checkFullDeck(cardsInHands(s.hands) + s.talon, context: "bidding cards")
            try require(
                s.activePlayers.contains(s.currentPlayer),
                "bidding currentPlayer \(s.currentPlayer) ∉ activePlayers"
            )
            try require(
                s.passed.isSubset(of: Set(s.activePlayers)),
                "bidding passed \(sorted(s.passed)) ⊄ activePlayers"
            )
        case let .awaitingDiscard(s):
            try checkActiveSeats(s.activePlayers)
            try checkHands(s.hands, seats: s.activePlayers, expected: 10)
            try require(s.talon.count == 2, "awaitingDiscard talon must be 2 cards, got \(s.talon.count)")
            try checkFullDeck(cardsInHands(s.hands) + s.talon, context: "awaitingDiscard cards")
            try require(
                s.activePlayers.contains(s.declarer),
                "awaitingDiscard declarer \(s.declarer) ∉ activePlayers"
            )
        case let .awaitingContract(s):
            try checkActiveSeats(s.activePlayers)
            try checkHands(s.hands, seats: s.activePlayers, expected: 10)
            try require(s.talon.count == 2, "awaitingContract talon must be 2 cards, got \(s.talon.count)")
            try require(s.discard.count == 2, "awaitingContract discard must be 2 cards, got \(s.discard.count)")
            try checkFullDeck(cardsInHands(s.hands) + s.discard, context: "awaitingContract cards")
            try require(
                s.activePlayers.contains(s.declarer),
                "awaitingContract declarer \(s.declarer) ∉ activePlayers"
            )
        case let .awaitingWhist(s):
            try checkActiveSeats(s.activePlayers)
            try checkHands(s.hands, seats: s.activePlayers, expected: 10)
            try require(s.talon.count == 2, "awaitingWhist talon must be 2 cards, got \(s.talon.count)")
            try require(s.discard.count == 2, "awaitingWhist discard must be 2 cards, got \(s.discard.count)")
            try checkFullDeck(cardsInHands(s.hands) + s.discard, context: "awaitingWhist cards")
            try require(
                s.activePlayers.contains(s.declarer),
                "awaitingWhist declarer \(s.declarer) ∉ activePlayers"
            )
            try require(
                s.activePlayers.contains(s.currentPlayer),
                "awaitingWhist currentPlayer \(s.currentPlayer) ∉ activePlayers"
            )
            try require(
                Set(s.defenders).isSubset(of: Set(s.activePlayers)),
                "defenders \(sorted(s.defenders)) ⊄ activePlayers"
            )
            try require(!s.defenders.contains(s.declarer), "declarer \(s.declarer) ∈ defenders")
        case let .awaitingDefenderMode(s):
            try checkActiveSeats(s.activePlayers)
            try checkHands(s.hands, seats: s.activePlayers, expected: 10)
            try require(s.talon.count == 2, "awaitingDefenderMode talon must be 2 cards, got \(s.talon.count)")
            try require(s.discard.count == 2, "awaitingDefenderMode discard must be 2 cards, got \(s.discard.count)")
            try checkFullDeck(cardsInHands(s.hands) + s.discard, context: "awaitingDefenderMode cards")
            try require(
                s.activePlayers.contains(s.declarer),
                "awaitingDefenderMode declarer \(s.declarer) ∉ activePlayers"
            )
            try require(
                s.activePlayers.contains(s.whister),
                "awaitingDefenderMode whister \(s.whister) ∉ activePlayers"
            )
        case let .playing(s):
            try checkActiveSeats(s.activePlayers)
            try require(s.talon.count == 2, "playing talon must be 2 cards, got \(s.talon.count)")
            try require(
                Set(s.hands.keys) == Set(s.activePlayers),
                "playing hand keys \(sorted(s.hands.keys)) ≠ activePlayers \(sorted(s.activePlayers))"
            )
            try require(
                Set(s.trickCounts.keys) == Set(s.activePlayers),
                "playing trickCounts keys \(sorted(s.trickCounts.keys)) ≠ activePlayers \(sorted(s.activePlayers))"
            )
            try require(
                s.activePlayers.contains(s.currentPlayer),
                "playing currentPlayer \(s.currentPlayer) ∉ activePlayers"
            )
            try require(
                s.activePlayers.contains(s.leader),
                "playing leader \(s.leader) ∉ activePlayers"
            )
            let expectedRemaining = 10 - s.completedTricks.count
            for (player, hand) in s.hands {
                let inFlight = s.currentTrick.contains(where: { $0.player == player }) ? 1 : 0
                try require(
                    hand.count + inFlight == expectedRemaining,
                    "\(player) hand \(hand.count) + inFlight \(inFlight) ≠ expected \(expectedRemaining)"
                )
                try require(Set(hand).count == hand.count, "\(player) holds duplicate cards")
            }
            let trickSum = s.trickCounts.values.reduce(0, +)
            try require(
                trickSum == s.completedTricks.count,
                "trickCounts sum \(trickSum) ≠ completedTricks \(s.completedTricks.count)"
            )
            let playedCards = s.completedTricks.flatMap { $0.plays.map(\.card) } + s.currentTrick.map(\.card)
            switch s.kind {
            case .game, .misere:
                try require(s.discard.count == 2, "playing discard must be 2 cards, got \(s.discard.count)")
                try checkFullDeck(cardsInHands(s.hands) + playedCards + s.discard, context: "playing cards")
            case .allPass:
                try require(s.discard.isEmpty, "all-pass playing discard must be empty, got \(s.discard.count)")
                try checkFullDeck(cardsInHands(s.hands) + playedCards + s.talon, context: "all-pass playing cards")
            }
            if let proposal = s.pendingSettlement {
                try require(s.currentTrick.isEmpty, "pending settlement requires an empty current trick")
                try require(
                    s.activePlayers.contains(proposal.proposer),
                    "settlement proposer \(proposal.proposer) ∉ activePlayers"
                )
                try require(
                    proposal.acceptedBy.isSubset(of: Set(s.activePlayers)),
                    "settlement acceptedBy \(sorted(proposal.acceptedBy)) ⊄ activePlayers"
                )
                try require(
                    proposal.acceptedBy.contains(proposal.proposer),
                    "settlement proposer must auto-accept"
                )
                try checkSettlement(
                    proposal.settlement,
                    activePlayers: s.activePlayers,
                    minimumTrickCounts: s.trickCounts,
                    context: "pending settlement"
                )
            }
        }
    }

    static func validateInvariants(_ snapshot: PreferansSnapshot) throws {
        try validateInvariants(snapshot.state)
        try require(snapshot.players.contains(snapshot.nextDealer), "nextDealer \(snapshot.nextDealer) is not in players")
        try snapshot.score.validate(players: snapshot.players)
        try checkPlayerReferences(snapshot.state, players: snapshot.players)
        switch snapshot.state {
        case let .dealFinished(result):
            try result.scoreDelta.validate(players: snapshot.players)
        case let .gameOver(summary):
            try checkGameOverSummary(
                summary,
                players: snapshot.players,
                score: snapshot.score,
                dealsPlayed: snapshot.dealsPlayed
            )
        default:
            break
        }
    }

    private static func require(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        if !condition {
            throw InvariantViolation(message: message())
        }
    }

    private static func checkActiveSeats(_ seats: [PlayerID]) throws {
        try require(seats.count == 3, "active seats must be 3, got \(seats.count): \(sorted(seats))")
        try require(Set(seats).count == seats.count, "duplicate seat in activePlayers: \(sorted(seats))")
    }

    private static func checkHands(
        _ hands: [PlayerID: [Card]],
        seats: [PlayerID],
        expected: Int,
        context: String = "hand"
    ) throws {
        try require(
            Set(hands.keys) == Set(seats),
            "\(context) keys \(sorted(hands.keys)) ≠ seats \(sorted(seats))"
        )
        for (player, hand) in hands {
            try require(
                hand.count == expected,
                "\(context) for \(player) has \(hand.count) cards, expected \(expected)"
            )
            try require(Set(hand).count == hand.count, "\(player) holds duplicate cards")
        }
    }

    private static func cardsInHands(_ hands: [PlayerID: [Card]]) -> [Card] {
        hands.values.flatMap { $0 }
    }

    private static func checkFullDeck(_ cards: [Card], context: String) throws {
        try require(cards.count == Deck.standard32.count, "\(context) has \(cards.count) cards, expected \(Deck.standard32.count)")
        try require(Set(cards).count == cards.count, "\(context) contains duplicate cards")
        try require(Set(cards) == Set(Deck.standard32), "\(context) must contain the standard Preferans deck")
    }

    private static func checkResult(_ result: DealResult, context: String) throws {
        try checkActiveSeats(result.activePlayers)
        try require(
            Set(result.trickCounts.keys) == Set(result.activePlayers),
            "\(context) trickCounts keys \(sorted(result.trickCounts.keys)) ≠ activePlayers \(sorted(result.activePlayers))"
        )
        if let initialHands = result.initialHands {
            try checkHands(initialHands, seats: result.activePlayers, expected: 10, context: "\(context) initialHands")
        }
        if let settlement = result.settlement {
            try checkSettlement(
                settlement,
                activePlayers: result.activePlayers,
                minimumTrickCounts: result.completedTricks.reduce(result.activePlayers.dictionary(filledWith: 0)) { counts, trick in
                    var updated = counts
                    updated[trick.winner, default: 0] += 1
                    return updated
                },
                context: context
            )
            try require(
                settlement.finalTrickCounts == result.trickCounts,
                "\(context) settlement counts must match result trickCounts"
            )
        }
    }

    private static func checkSettlement(
        _ settlement: TrickSettlement,
        activePlayers: [PlayerID],
        minimumTrickCounts: [PlayerID: Int],
        context: String
    ) throws {
        try require(
            activePlayers.contains(settlement.target),
            "\(context) target \(settlement.target) ∉ activePlayers"
        )
        try require(
            Set(settlement.finalTrickCounts.keys) == Set(activePlayers),
            "\(context) final trick-count keys \(sorted(settlement.finalTrickCounts.keys)) ≠ activePlayers \(sorted(activePlayers))"
        )
        try require(
            settlement.finalTrickCounts[settlement.target] == settlement.targetTricks,
            "\(context) targetTricks does not match final trick counts"
        )
        let total = settlement.finalTrickCounts.values.reduce(0, +)
        try require(total == 10, "\(context) final trick counts total \(total), expected 10")
        for player in activePlayers {
            let minimum = minimumTrickCounts[player] ?? 0
            let final = settlement.finalTrickCounts[player] ?? 0
            try require(
                final >= minimum,
                "\(context) final tricks for \(player) \(final) < already won \(minimum)"
            )
        }
    }

    private static func checkPlayerReferences(_ state: DealState, players: [PlayerID]) throws {
        let playerSet = Set(players)
        func check(_ player: PlayerID, context: String) throws {
            try require(playerSet.contains(player), "\(context) \(player) is not in players")
        }
        func checkAll(_ ids: [PlayerID], context: String) throws {
            try require(Set(ids).isSubset(of: playerSet), "\(context) \(sorted(ids.filter { !playerSet.contains($0) })) contains unknown players")
        }

        switch state {
        case .waitingForDeal:
            return
        case let .bidding(s):
            try check(s.dealer, context: "bidding dealer")
            try checkAll(s.activePlayers, context: "bidding activePlayers")
            try checkAll(Array(s.passed), context: "bidding passed")
        case let .awaitingDiscard(s):
            try check(s.dealer, context: "awaitingDiscard dealer")
            try checkAll(s.activePlayers, context: "awaitingDiscard activePlayers")
            try check(s.declarer, context: "awaitingDiscard declarer")
        case let .awaitingContract(s):
            try check(s.dealer, context: "awaitingContract dealer")
            try checkAll(s.activePlayers, context: "awaitingContract activePlayers")
            try check(s.declarer, context: "awaitingContract declarer")
        case let .awaitingWhist(s):
            try check(s.dealer, context: "awaitingWhist dealer")
            try checkAll(s.activePlayers, context: "awaitingWhist activePlayers")
            try check(s.declarer, context: "awaitingWhist declarer")
            try checkAll(s.defenders, context: "awaitingWhist defenders")
            try check(s.currentPlayer, context: "awaitingWhist currentPlayer")
        case let .awaitingDefenderMode(s):
            try check(s.dealer, context: "awaitingDefenderMode dealer")
            try checkAll(s.activePlayers, context: "awaitingDefenderMode activePlayers")
            try check(s.declarer, context: "awaitingDefenderMode declarer")
            try checkAll(s.defenders, context: "awaitingDefenderMode defenders")
            try check(s.whister, context: "awaitingDefenderMode whister")
        case let .playing(s):
            try check(s.dealer, context: "playing dealer")
            try checkAll(s.activePlayers, context: "playing activePlayers")
            try check(s.leader, context: "playing leader")
            try check(s.currentPlayer, context: "playing currentPlayer")
        case let .dealFinished(result):
            try checkAll(result.activePlayers, context: "dealFinished activePlayers")
        case let .gameOver(summary):
            try checkAll(summary.lastDeal.activePlayers, context: "gameOver activePlayers")
            try checkAll(summary.standings.map(\.player), context: "gameOver standings")
        }
    }

    private static func checkGameOverSummary(
        _ summary: MatchSummary,
        players: [PlayerID],
        score: ScoreSheet,
        dealsPlayed: Int
    ) throws {
        try require(summary.finalScore == score, "gameOver finalScore must match engine score")
        try require(summary.dealsPlayed == dealsPlayed, "gameOver dealsPlayed must match engine dealsPlayed")
        try checkResult(summary.lastDeal, context: "gameOver lastDeal")
        try summary.lastDeal.scoreDelta.validate(players: players)

        let standingsPlayers = summary.standings.map(\.player)
        try require(Set(standingsPlayers) == Set(players), "gameOver standings players must match players")
        try require(Set(standingsPlayers).count == standingsPlayers.count, "gameOver standings players must be unique")
        let balances = score.normalizedBalances()
        for standing in summary.standings {
            try require(standing.pool == (score.pool[standing.player] ?? 0), "gameOver standing pool must match score")
            try require(standing.mountain == (score.mountain[standing.player] ?? 0), "gameOver standing mountain must match score")
            let expectedBalance = balances[standing.player] ?? 0
            try require(abs(standing.balance - expectedBalance) < 0.000_001, "gameOver standing balance must match score")
        }
    }

    private static func sorted<S: Sequence>(_ ids: S) -> [String] where S.Element == PlayerID {
        ids.map(\.rawValue).sorted()
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
