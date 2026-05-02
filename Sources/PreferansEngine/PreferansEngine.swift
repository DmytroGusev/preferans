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
        switch action {
        case let .startDeal(dealer, deck):
            return try applyStartDeal(dealer: dealer, deck: deck)
        case let .bid(player, call):
            return try applyBid(player: player, call: call)
        case let .discard(player, cards):
            return try applyDiscard(player: player, cards: cards)
        case let .declareContract(player, contract):
            return try applyDeclareContract(player: player, contract: contract)
        case let .whist(player, call):
            return try applyWhist(player: player, call: call)
        case let .chooseDefenderMode(player, mode):
            return try applyChooseDefenderMode(player: player, mode: mode)
        case let .playCard(player, card):
            return try applyPlayCard(player: player, card: card)
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
        guard case let .playing(playing) = state, playing.currentPlayer == player else {
            return []
        }
        return (playing.hands[player] ?? []).filter { isLegal(card: $0, by: player, in: playing) }
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

    /// Whist requirement on a contract, with totus-specific overrides applied.
    private func effectiveWhistRequirement(for contract: GameContract) -> Int {
        if contract.tricks == 10 && match.totus.requireWhistOnTenTricks {
            return 1
        }
        return rules.whistRequirement(for: contract)
    }

    private static func validate(players: [PlayerID]) throws {
        guard players.count == 3 || players.count == 4 else {
            throw PreferansError.invalidPlayers("PreferansEngine requires exactly 3 or 4 players.")
        }
        guard Set(players).count == players.count else {
            throw PreferansError.invalidPlayers("PlayerID values must be unique.")
        }
    }

    private mutating func applyStartDeal(dealer suppliedDealer: PlayerID?, deck suppliedDeck: [Card]?) throws -> [PreferansEvent] {
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

        nextDealer = player(after: dealer)
        state = .bidding(
            BiddingState(
                dealer: dealer,
                activePlayers: activePlayers,
                hands: deal.hands,
                talon: deal.talon,
                currentPlayer: activePlayers[0]
            )
        )

        return [.dealStarted(dealer: dealer, activePlayers: activePlayers)]
    }

    private mutating func applyBid(player: PlayerID, call: BidCall) throws -> [PreferansEvent] {
        guard case var .bidding(bidding) = state else {
            throw PreferansError.invalidState(expected: "bidding", actual: state.description)
        }
        try validateCurrent(player, expected: bidding.currentPlayer)
        guard bidding.activePlayers.contains(player), !bidding.passed.contains(player) else {
            throw PreferansError.illegalBid("Player is not active in the auction.")
        }

        let record = AuctionCall(player: player, call: call)
        var events: [PreferansEvent] = [.bidAccepted(record)]
        bidding.calls.append(record)

        switch call {
        case .pass:
            bidding.passed.insert(player)
        case let .bid(bid):
            guard isLegalBid(bid, by: player, in: bidding) else {
                throw PreferansError.illegalBid("\(bid) is not legal for \(player).")
            }
            bidding.highestBid = bid
            bidding.highestBidder = player
            bidding.significantBidByPlayer[player] = bid
        }

        if bidding.highestBid == nil && bidding.passed.count == bidding.activePlayers.count {
            let playing = makePlayingState(
                dealer: bidding.dealer,
                activePlayers: bidding.activePlayers,
                hands: bidding.hands,
                talon: bidding.talon,
                discard: [],
                kind: .allPass(AllPassPlayContext(talonPolicy: rules.allPassTalonPolicy))
            )
            state = .playing(playing)
            events.append(.allPassed)
            events.append(.playStarted(playing.kind))
            return events
        }

        let remaining = bidding.activePlayers.filter { !bidding.passed.contains($0) }
        if let highestBid = bidding.highestBid,
           let declarer = bidding.highestBidder,
           remaining.count == 1 {
            state = .awaitingDiscard(
                ExchangeState(
                    dealer: bidding.dealer,
                    activePlayers: bidding.activePlayers,
                    hands: bidding.hands,
                    talon: bidding.talon,
                    declarer: declarer,
                    finalBid: highestBid,
                    auction: bidding.calls
                )
            )
            events.append(.auctionWon(declarer: declarer, bid: highestBid))
            return events
        }

        guard let next = nextBidder(after: player, in: bidding) else {
            throw PreferansError.illegalBid("No next bidder is available.")
        }
        bidding.currentPlayer = next
        state = .bidding(bidding)
        return events
    }

    private mutating func applyDiscard(player: PlayerID, cards: [Card]) throws -> [PreferansEvent] {
        guard case var .awaitingDiscard(exchange) = state else {
            throw PreferansError.invalidState(expected: "awaitingDiscard", actual: state.description)
        }
        try validateCurrent(player, expected: exchange.declarer)
        guard cards.count == 2 else {
            throw PreferansError.illegalCardPlay("Discard must contain exactly two cards.")
        }
        guard Set(cards).count == cards.count else {
            throw PreferansError.duplicateCards(cards)
        }

        let originalHand = exchange.hands[player] ?? []
        var combined = originalHand + exchange.talon
        for card in cards {
            guard let index = combined.firstIndex(of: card) else {
                throw PreferansError.cardNotInHand(player: player, card: card)
            }
            combined.remove(at: index)
        }
        guard combined.count == 10 else {
            throw PreferansError.illegalCardPlay("Declarer must keep ten cards after discard.")
        }
        exchange.hands[player] = combined.sorted()

        let exchangeEvent = PreferansEvent.talonExchanged(
            declarer: player,
            talon: exchange.talon,
            discard: cards
        )

        switch exchange.finalBid {
        case .misere:
            let playing = makePlayingState(
                dealer: exchange.dealer,
                activePlayers: exchange.activePlayers,
                hands: exchange.hands,
                talon: exchange.talon,
                discard: cards,
                kind: .misere(MiserePlayContext(declarer: player))
            )
            state = .playing(playing)
            return [exchangeEvent, .playStarted(playing.kind)]
        case .game, .totus:
            // Totus uses the same contract-declaration step but the legal
            // contract list is constrained to 10-trick options; see
            // ``legalContractDeclarations(for:)``.
            state = .awaitingContract(
                ContractDeclarationState(
                    dealer: exchange.dealer,
                    activePlayers: exchange.activePlayers,
                    hands: exchange.hands,
                    talon: exchange.talon,
                    discard: cards,
                    declarer: player,
                    finalBid: exchange.finalBid,
                    auction: exchange.auction
                )
            )
            return [exchangeEvent]
        }
    }

    private mutating func applyDeclareContract(player: PlayerID, contract: GameContract) throws -> [PreferansEvent] {
        guard case let .awaitingContract(declaration) = state else {
            throw PreferansError.invalidState(expected: "awaitingContract", actual: state.description)
        }
        try validateCurrent(player, expected: declaration.declarer)
        let bonusPool: Int
        switch declaration.finalBid {
        case let .game(finalGameBid):
            guard contract >= finalGameBid else {
                throw PreferansError.invalidContract("Declared contract cannot be below the auction bid.")
            }
            bonusPool = 0
        case .totus:
            guard contract.tricks == 10 else {
                throw PreferansError.invalidContract("Totus declaration must be a 10-trick contract.")
            }
            bonusPool = match.totus.bonusPool
        case .misere:
            throw PreferansError.invalidContract("Misere does not enter contract declaration.")
        }

        let defenders = defenders(after: player, activePlayers: declaration.activePlayers)
        let whist = WhistState(
            dealer: declaration.dealer,
            activePlayers: declaration.activePlayers,
            hands: declaration.hands,
            talon: declaration.talon,
            discard: declaration.discard,
            declarer: player,
            contract: contract,
            defenders: defenders,
            currentPlayer: defenders[0],
            bonusPoolOnSuccess: bonusPool
        )
        state = .awaitingWhist(whist)
        return [.contractDeclared(declarer: player, contract: contract)]
    }

    private mutating func applyWhist(player: PlayerID, call: WhistCall) throws -> [PreferansEvent] {
        guard case var .awaitingWhist(whist) = state else {
            throw PreferansError.invalidState(expected: "awaitingWhist", actual: state.description)
        }
        try validateCurrent(player, expected: whist.currentPlayer)
        guard legalWhistCalls(in: whist, for: player).contains(call) else {
            throw PreferansError.illegalWhist("\(call) is not legal for \(player).")
        }

        let record = WhistCallRecord(player: player, call: call)
        whist.calls.append(record)
        var events: [PreferansEvent] = [.whistAccepted(record)]

        let first = whist.defenders[0]
        let second = whist.defenders[1]

        switch whist.flow {
        case .normal:
            if player == first {
                whist.currentPlayer = second
                state = .awaitingWhist(whist)
                return events
            }

            let firstCall = whist.calls.first { $0.player == first }?.call
            if firstCall == .pass {
                switch call {
                case .pass:
                    events.append(contentsOf: scorePassedOut(whist))
                    return events
                case .whist:
                    state = .awaitingDefenderMode(makeDefenderModeState(whist: whist, whister: second))
                    return events
                case .halfWhist:
                    whist.currentPlayer = first
                    whist.flow = .firstDefenderSecondChance(halfWhister: second)
                    state = .awaitingWhist(whist)
                    return events
                }
            }

            switch call {
            case .pass:
                state = .awaitingDefenderMode(makeDefenderModeState(whist: whist, whister: first))
                return events
            case .whist:
                let playing = startGamePlay(from: whist, whisters: [first, second], mode: .closed)
                events.append(.playStarted(playing.kind))
                return events
            case .halfWhist:
                throw PreferansError.illegalWhist("Half-whist is only legal after first defender passes.")
            }

        case let .firstDefenderSecondChance(halfWhister):
            switch call {
            case .pass:
                events.append(contentsOf: scoreHalfWhist(whist, halfWhister: halfWhister))
                return events
            case .whist:
                let playing = startGamePlay(from: whist, whisters: [first, halfWhister], mode: .closed)
                events.append(.playStarted(playing.kind))
                return events
            case .halfWhist:
                throw PreferansError.illegalWhist("Half-whist is not legal on second chance.")
            }
        }
    }

    private mutating func applyChooseDefenderMode(player: PlayerID, mode: DefenderPlayMode) throws -> [PreferansEvent] {
        guard case let .awaitingDefenderMode(defenderMode) = state else {
            throw PreferansError.invalidState(expected: "awaitingDefenderMode", actual: state.description)
        }
        try validateCurrent(player, expected: defenderMode.whister)

        let playing = makePlayingState(
            dealer: defenderMode.dealer,
            activePlayers: defenderMode.activePlayers,
            hands: defenderMode.hands,
            talon: defenderMode.talon,
            discard: defenderMode.discard,
            kind: .game(
                GamePlayContext(
                    declarer: defenderMode.declarer,
                    contract: defenderMode.contract,
                    defenders: defenderMode.defenders,
                    whisters: [defenderMode.whister],
                    defenderPlayMode: mode,
                    whistCalls: defenderMode.whistCalls,
                    bonusPoolOnSuccess: defenderMode.bonusPoolOnSuccess
                )
            )
        )
        state = .playing(playing)
        return [.defenderModeChosen(whister: player, mode: mode), .playStarted(playing.kind)]
    }

    private mutating func applyPlayCard(player: PlayerID, card: Card) throws -> [PreferansEvent] {
        guard case var .playing(playing) = state else {
            throw PreferansError.invalidState(expected: "playing", actual: state.description)
        }
        try validateCurrent(player, expected: playing.currentPlayer)
        guard let cardIndex = playing.hands[player]?.firstIndex(of: card) else {
            throw PreferansError.cardNotInHand(player: player, card: card)
        }
        guard isLegal(card: card, by: player, in: playing) else {
            throw PreferansError.illegalCardPlay("\(card) is not legal for \(player).")
        }

        playing.hands[player]?.remove(at: cardIndex)
        let play = CardPlay(player: player, card: card)
        playing.currentTrick.append(play)
        var events: [PreferansEvent] = [.cardPlayed(play)]

        if playing.currentTrick.count < playing.activePlayers.count {
            playing.currentPlayer = nextActivePlayer(after: player, activePlayers: playing.activePlayers)
            state = .playing(playing)
            return events
        }

        let leadSuit = requiredSuit(for: playing) ?? playing.currentTrick[0].card.suit
        let winner = trickWinner(for: playing.currentTrick, leadSuit: leadSuit, trump: playing.kind.trumpSuit)
        let trick = Trick(
            leader: playing.leader,
            leadSuit: leadSuit,
            plays: playing.currentTrick,
            winner: winner
        )
        playing.completedTricks.append(trick)
        playing.trickCounts[winner, default: 0] += 1
        playing.currentTrick = []
        playing.leader = winner
        playing.currentPlayer = winner
        events.append(.trickCompleted(trick))

        if playing.isComplete {
            let result = scoreCompletedPlay(playing)
            events.append(contentsOf: finalize(result))
            return events
        }

        state = .playing(playing)
        return events
    }

    private func validateCurrent(_ actual: PlayerID, expected: PlayerID) throws {
        guard actual == expected else {
            throw PreferansError.notPlayersTurn(expected: expected, actual: actual)
        }
    }

    private func isLegalBid(_ bid: ContractBid, by player: PlayerID, in bidding: BiddingState) -> Bool {
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

    private func legalWhistCalls(in whist: WhistState, for player: PlayerID) -> [WhistCall] {
        guard whist.defenders.contains(player), whist.currentPlayer == player else {
            return []
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

    /// Active rotation for a deal with the given dealer. In 3-player matches
    /// every seat is active and the rotation starts immediately after the
    /// dealer; in 4-player matches the dealer sits out and the next three
    /// seats fill the rotation. Exposed publicly so test harnesses and UI
    /// fixtures can pre-compute the rotation before calling ``startDeal``.
    public func activePlayers(forDealer dealer: PlayerID) -> [PlayerID] {
        let start = player(after: dealer)
        var ordered: [PlayerID] = []
        var current = start
        repeat {
            if players.count == 3 || current != dealer {
                ordered.append(current)
            }
            current = player(after: current)
        } while current != start
        return ordered
    }

    private func player(after player: PlayerID) -> PlayerID {
        guard let index = players.firstIndex(of: player) else { return players[0] }
        return players[(index + 1) % players.count]
    }

    private func nextActivePlayer(after player: PlayerID, activePlayers: [PlayerID]) -> PlayerID {
        guard let index = activePlayers.firstIndex(of: player) else { return activePlayers[0] }
        return activePlayers[(index + 1) % activePlayers.count]
    }

    private func nextBidder(after player: PlayerID, in bidding: BiddingState) -> PlayerID? {
        guard let index = bidding.activePlayers.firstIndex(of: player) else { return nil }
        for offset in 1...bidding.activePlayers.count {
            let candidate = bidding.activePlayers[(index + offset) % bidding.activePlayers.count]
            if !bidding.passed.contains(candidate) {
                return candidate
            }
        }
        return nil
    }

    private func defenders(after declarer: PlayerID, activePlayers: [PlayerID]) -> [PlayerID] {
        var defenders: [PlayerID] = []
        var current = nextActivePlayer(after: declarer, activePlayers: activePlayers)
        while current != declarer {
            defenders.append(current)
            current = nextActivePlayer(after: current, activePlayers: activePlayers)
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
        var deck = deck
        var hands = Dictionary(uniqueKeysWithValues: activePlayers.map { ($0, [Card]()) })
        var talon: [Card] = []

        for packet in 0..<5 {
            for player in activePlayers {
                hands[player, default: []].append(deck.removeFirst())
                hands[player, default: []].append(deck.removeFirst())
            }
            if packet == 0 {
                talon.append(deck.removeFirst())
                talon.append(deck.removeFirst())
            }
        }

        for player in activePlayers {
            hands[player]?.sort()
        }
        return (hands, talon)
    }

    private func makePlayingState(
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

    private func makeDefenderModeState(whist: WhistState, whister: PlayerID) -> DefenderModeState {
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

    @discardableResult
    private mutating func startGamePlay(
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
        state = .playing(playing)
        return playing
    }

    private mutating func scorePassedOut(_ whist: WhistState) -> [PreferansEvent] {
        var delta = ScoreDelta(players: players)
        delta.addPool(whist.contract.value + whist.bonusPoolOnSuccess, to: whist.declarer)
        let result = DealResult(
            kind: .passedOut,
            activePlayers: whist.activePlayers,
            trickCounts: Dictionary(uniqueKeysWithValues: whist.activePlayers.map { ($0, 0) }),
            completedTricks: [],
            scoreDelta: delta
        )
        return finalize(result)
    }

    private mutating func scoreHalfWhist(_ whist: WhistState, halfWhister: PlayerID) -> [PreferansEvent] {
        var delta = ScoreDelta(players: players)
        delta.addPool(whist.contract.value, to: whist.declarer)
        delta.addWhists(
            whist.contract.value * (effectiveWhistRequirement(for: whist.contract) / 2),
            writer: halfWhister,
            on: whist.declarer
        )
        let result = DealResult(
            kind: .halfWhist(declarer: whist.declarer, contract: whist.contract, halfWhister: halfWhister),
            activePlayers: whist.activePlayers,
            trickCounts: Dictionary(uniqueKeysWithValues: whist.activePlayers.map { ($0, 0) }),
            completedTricks: [],
            scoreDelta: delta
        )
        return finalize(result)
    }

    /// Applies the deal's score delta, increments the deal counter, and
    /// transitions to ``DealState/gameOver`` when the pool sum has reached the
    /// match's pool target. Otherwise transitions to ``DealState/dealFinished``.
    /// Returns the events the caller should append (always `dealScored`,
    /// optionally followed by `matchEnded`).
    private mutating func finalize(_ result: DealResult) -> [PreferansEvent] {
        score.apply(result.scoreDelta)
        dealsPlayed += 1
        var events: [PreferansEvent] = [.dealScored(result)]
        let totalPool = score.pool.values.reduce(0, +)
        if totalPool >= match.poolTarget {
            let summary = makeMatchSummary(lastDeal: result)
            state = .gameOver(summary)
            events.append(.matchEnded(summary))
        } else {
            state = .dealFinished(result)
        }
        return events
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

    private func requiredSuit(for playing: PlayingState) -> Suit? {
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

    private func isLegal(card: Card, by player: PlayerID, in playing: PlayingState) -> Bool {
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

    private func trickWinner(for trick: [CardPlay], leadSuit: Suit, trump: Suit?) -> PlayerID {
        trick.max { lhs, rhs in
            compare(lhs.card, rhs.card, leadSuit: leadSuit, trump: trump) == .orderedAscending
        }!.player
    }

    private func compare(_ left: Card, _ right: Card, leadSuit: Suit, trump: Suit?) -> ComparisonResult {
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

    private func scoreCompletedPlay(_ playing: PlayingState) -> DealResult {
        switch playing.kind {
        case let .game(context):
            return scoreGame(playing, context: context)
        case let .misere(context):
            return scoreMisere(playing, context: context)
        case .allPass:
            return scoreAllPass(playing)
        }
    }

    private func scoreGame(_ playing: PlayingState, context: GamePlayContext) -> DealResult {
        var delta = ScoreDelta(players: players)
        let declarerTricks = playing.trickCounts[context.declarer] ?? 0
        let defenderTricks = context.defenders.reduce(0) { $0 + (playing.trickCounts[$1] ?? 0) }
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

        if context.whisters.count == 1, let whister = context.whisters.first {
            let whistTricks: Int
            switch rules.singleWhistScoring {
            case .greedy:
                whistTricks = defenderTricks
            case .ownHandOnly:
                whistTricks = playing.trickCounts[whister] ?? 0
            }
            delta.addWhists(value * whistTricks, writer: whister, on: context.declarer)
        } else {
            for whister in context.whisters {
                delta.addWhists(value * (playing.trickCounts[whister] ?? 0), writer: whister, on: context.declarer)
            }
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
            scoreDelta: delta
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
            let own = trickCounts[whister] ?? 0
            let missing = max(0, quota - own)
            delta.addMountain(missing * value, to: whister)
        }
    }

    private func scoreMisere(_ playing: PlayingState, context: MiserePlayContext) -> DealResult {
        var delta = ScoreDelta(players: players)
        let tricks = playing.trickCounts[context.declarer] ?? 0
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
            scoreDelta: delta
        )
    }

    private func scoreAllPass(_ playing: PlayingState) -> DealResult {
        var delta = ScoreDelta(players: players)
        let multiplier: Int
        let amnesty: Bool
        switch rules.allPassPenaltyPolicy {
        case let .perTrick(m, a):
            multiplier = m
            amnesty = a
        }
        let minimum = playing.activePlayers.map { playing.trickCounts[$0] ?? 0 }.min() ?? 0
        for player in playing.activePlayers {
            let tricks = playing.trickCounts[player] ?? 0
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
            scoreDelta: delta
        )
    }
}
