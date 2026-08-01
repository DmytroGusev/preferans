import Foundation

// MARK: - Invariant validation

extension PreferansEngine {
    /// Postcondition check called after every successful `apply(_:)` and on
    /// snapshot rehydration. Delegates to ``validateInvariants(_:)`` and
    /// traps via `precondition` on violation — these are engine-internal
    /// bugs, not recoverable input errors. The throwing validator exists so
    /// tests can verify each invariant fires without crashing the process.
    /// Adding new state arms or new mutators? Add the matching invariant in
    /// ``validateInvariants(_:)``.
    func assertInvariants(file: StaticString = #file, line: UInt = #line) {
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
            try checkBiddingLedger(s)
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
            try checkExchangedTalon(
                s.talon,
                declarer: s.declarer,
                hands: s.hands,
                discard: s.discard,
                context: "awaitingContract"
            )
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
            try checkExchangedTalon(
                s.talon,
                declarer: s.declarer,
                hands: s.hands,
                discard: s.discard,
                context: "awaitingWhist"
            )
            try require(
                s.activePlayers.contains(s.declarer),
                "awaitingWhist declarer \(s.declarer) ∉ activePlayers"
            )
            try require(
                s.activePlayers.contains(s.currentPlayer),
                "awaitingWhist currentPlayer \(s.currentPlayer) ∉ activePlayers"
            )
            try checkDefendingSide(
                activePlayers: s.activePlayers,
                declarer: s.declarer,
                defenders: s.defenders,
                context: "awaitingWhist"
            )
            try require(
                s.defenders.contains(s.currentPlayer),
                "awaitingWhist currentPlayer must be a defender"
            )
            try require(
                s.bonusPoolOnSuccess >= 0,
                "awaitingWhist bonusPoolOnSuccess cannot be negative"
            )
            try checkWhistDecisionFlow(s)
        case let .awaitingDefenderMode(s):
            try checkActiveSeats(s.activePlayers)
            try checkHands(s.hands, seats: s.activePlayers, expected: 10)
            try require(s.talon.count == 2, "awaitingDefenderMode talon must be 2 cards, got \(s.talon.count)")
            try require(s.discard.count == 2, "awaitingDefenderMode discard must be 2 cards, got \(s.discard.count)")
            try checkFullDeck(cardsInHands(s.hands) + s.discard, context: "awaitingDefenderMode cards")
            try checkExchangedTalon(
                s.talon,
                declarer: s.declarer,
                hands: s.hands,
                discard: s.discard,
                context: "awaitingDefenderMode"
            )
            try require(
                s.activePlayers.contains(s.declarer),
                "awaitingDefenderMode declarer \(s.declarer) ∉ activePlayers"
            )
            try checkDefendingSide(
                activePlayers: s.activePlayers,
                declarer: s.declarer,
                defenders: s.defenders,
                context: "awaitingDefenderMode"
            )
            try require(
                s.defenders.contains(s.whister),
                "awaitingDefenderMode whister must be a defender"
            )
            try require(
                s.bonusPoolOnSuccess >= 0,
                "awaitingDefenderMode bonusPoolOnSuccess cannot be negative"
            )
            try checkDefenderModeFlow(s)
        case let .playing(s):
            try checkActiveSeats(s.activePlayers)
            try require(s.talon.count == 2, "playing talon must be 2 cards, got \(s.talon.count)")
            try require(
                Set(s.hands.keys) == Set(s.activePlayers),
                "playing hand keys \(sorted(s.hands.keys)) ≠ activePlayers \(sorted(s.activePlayers))"
            )
            try require(
                Set(s.trickCounts.keys) == Set(s.trickTakingPlayers),
                "playing trickCounts keys \(sorted(s.trickCounts.keys)) ≠ trick takers \(sorted(s.trickTakingPlayers))"
            )
            try require(
                s.activePlayers.contains(s.currentPlayer),
                "playing currentPlayer \(s.currentPlayer) ∉ activePlayers"
            )
            try require(
                s.activePlayers.contains(s.leader)
                    || (s.isClassicFourPlayerAllPass
                        && s.completedTricks.count < 2
                        && s.leader == s.dealer),
                "playing leader \(s.leader) is neither active nor the opening raspasy dealer"
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
            let completedTrickCounts = s.completedTricks.reduce(
                s.trickTakingPlayers.dictionary(filledWith: 0)
            ) { counts, trick in
                var updated = counts
                updated[trick.winner, default: 0] += 1
                return updated
            }
            try require(
                s.trickCounts == completedTrickCounts,
                "playing trickCounts must match completed-trick winners"
            )
            try require(
                s.completedTricks.allSatisfy { s.trickCounts.keys.contains($0.winner) },
                "completed trick winner must be a trick-taking player"
            )
            let playedCards = s.completedTricks.flatMap { $0.plays.map(\.card) } + s.currentTrick.map(\.card)
            switch s.kind {
            case let .game(ctx):
                try require(s.discard.count == 2, "playing discard must be 2 cards, got \(s.discard.count)")
                try checkFullDeck(cardsInHands(s.hands) + playedCards + s.discard, context: "playing cards")
                try checkExchangedTalon(
                    s.talon,
                    declarer: ctx.declarer,
                    hands: s.hands,
                    discard: s.discard,
                    playedCards: playedCards,
                    context: "playing"
                )
                // 10-trick contracts skip the whist phase, so an empty
                // whisters list is intentional. For shorter contracts
                // every whister must be a defender and the declarer
                // is never on the defending side.
                try require(
                    Set(ctx.whisters).isSubset(of: Set(ctx.defenders)),
                    "playing whisters \(sorted(ctx.whisters)) ⊄ defenders \(sorted(ctx.defenders))"
                )
                try require(
                    !ctx.defenders.contains(ctx.declarer),
                    "playing declarer \(ctx.declarer) ∈ defenders"
                )
                // Open single-whist greedy play is the canonical "whister
                // pulls the passer's dummy hand" arrangement. The control
                // resolver requires a unique whister to act on the passer's
                // behalf — there are exactly two defenders and exactly one
                // is the whister, so the controller is unambiguous. This
                // invariant pins that down so a future bug in the whist
                // reducer can't quietly produce a single-whister state with
                // no defender to control.
                if ctx.whisters.count == 1, ctx.defenders.count == 2 {
                    let whister = ctx.whisters[0]
                    try require(
                        ctx.defenders.contains(whister),
                        "single whister \(whister) ∉ defenders \(sorted(ctx.defenders))"
                    )
                }
            case .misere:
                try require(s.discard.count == 2, "playing discard must be 2 cards, got \(s.discard.count)")
                try checkFullDeck(cardsInHands(s.hands) + playedCards + s.discard, context: "playing cards")
                if case let .misere(ctx) = s.kind {
                    try checkExchangedTalon(
                        s.talon,
                        declarer: ctx.declarer,
                        hands: s.hands,
                        discard: s.discard,
                        playedCards: playedCards,
                        context: "playing"
                    )
                }
            case .allPass:
                try require(s.discard.isEmpty, "all-pass playing discard must be empty, got \(s.discard.count)")
                try checkFullDeck(cardsInHands(s.hands) + playedCards + s.talon, context: "all-pass playing cards")
            }
            try checkPlayedHistory(s)
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
        try require(snapshot.dealsPlayed >= 0, "dealsPlayed cannot be negative")
        try require(snapshot.consecutiveAllPassDeals >= 0, "consecutiveAllPassDeals cannot be negative")
        try require(
            snapshot.consecutiveAllPassDeals <= snapshot.dealsPlayed,
            "consecutiveAllPassDeals \(snapshot.consecutiveAllPassDeals) cannot exceed dealsPlayed \(snapshot.dealsPlayed)"
        )
        switch snapshot.state {
        case let .dealFinished(result):
            try checkRaspasySeriesCounter(
                result.kind,
                consecutiveAllPassDeals: snapshot.consecutiveAllPassDeals,
                context: "dealFinished"
            )
        case let .gameOver(summary):
            try checkRaspasySeriesCounter(
                summary.lastDeal.kind,
                consecutiveAllPassDeals: snapshot.consecutiveAllPassDeals,
                context: "gameOver"
            )
        default:
            break
        }
        try require(snapshot.rules.configurationError == nil, "invalid rules: \(snapshot.rules.configurationError ?? "unknown")")
        try checkMatchSettings(snapshot.match, playerCount: snapshot.players.count)
        try checkTenTrickDefenseState(
            snapshot.state,
            rules: snapshot.rules,
            match: snapshot.match
        )
        try snapshot.score.validate(players: snapshot.players)
        try checkScoreAgainstMatch(snapshot.score, match: snapshot.match)
        try checkPlayerReferences(snapshot.state, players: snapshot.players)
        let poolIsClosed = snapshot.match.isPoolClosed(snapshot.score)
        switch snapshot.state {
        case let .dealFinished(result):
            try require(!poolIsClosed, "dealFinished score must remain below the pool-closing target")
            try result.scoreDelta.validate(players: snapshot.players)
        case let .gameOver(summary):
            try require(poolIsClosed, "gameOver score must satisfy the pool-closing policy")
            try checkGameOverSummary(
                summary,
                players: snapshot.players,
                score: snapshot.score,
                dealsPlayed: snapshot.dealsPlayed,
                rules: snapshot.rules,
                match: snapshot.match
            )
        default:
            try require(!poolIsClosed, "an open deal state cannot carry a closed pulka")
            break
        }
    }

    private static func checkMatchSettings(_ match: MatchSettings, playerCount: Int) throws {
        let error = match.configurationError(playerCount: playerCount)
        try require(error == nil, "invalid match: \(error ?? "unknown")")
    }

    /// Ten-trick checking is a rule-sensitive state invariant. With the
    /// optional whist convention disabled, play starts immediately with every
    /// hand open and no whist ledger. With it enabled, normal pass/whist calls
    /// precede play; half-whist is never legal at a one-trick quota. Recovery
    /// must not reinterpret one form as the other.
    private static func checkTenTrickDefenseState(
        _ state: DealState,
        rules: PreferansRules,
        match: MatchSettings
    ) throws {
        let whistDecisionEnabled = rules.requireWhistOnTenTrickContracts
            || match.totus.requireWhistOnTenTricks

        func checkCalls(_ calls: [WhistCallRecord], context: String) throws {
            try require(
                calls.allSatisfy { $0.call != .halfWhist },
                "\(context) cannot contain half-whist on a ten-trick contract"
            )
        }

        func checkResult(_ result: DealResult, context: String) throws {
            guard case let .game(_, contract, whisters) = result.kind,
                  contract.tricks == 10 else { return }
            if whisters.isEmpty {
                try require(
                    !whistDecisionEnabled,
                    "\(context) cannot record an open ten-trick check when whist decisions are enabled"
                )
            } else {
                try require(
                    whistDecisionEnabled,
                    "\(context) cannot record ten-trick whisters when the whist convention is disabled"
                )
            }
        }

        switch state {
        case let .awaitingWhist(whist) where whist.contract.tricks == 10:
            try require(whistDecisionEnabled, "ten-trick whist state requires the whist convention")
            try checkCalls(whist.calls, context: "ten-trick whist state")
        case let .awaitingDefenderMode(mode) where mode.contract.tricks == 10:
            try require(whistDecisionEnabled, "ten-trick defender mode requires the whist convention")
            try checkCalls(mode.whistCalls, context: "ten-trick defender mode")
        case let .playing(playing):
            guard case let .game(context) = playing.kind,
                  context.contract.tricks == 10 else { return }
            try checkCalls(context.whistCalls, context: "ten-trick play")
            let isOpenCheck = context.whisters.isEmpty && context.whistCalls.isEmpty
            if isOpenCheck {
                try require(!whistDecisionEnabled, "open ten-trick check conflicts with enabled whist decisions")
                try require(context.defenderPlayMode == .open, "unwhisted ten-trick check must expose all hands")
            } else {
                try require(whistDecisionEnabled, "ten-trick whist play requires the whist convention")
            }
        case let .dealFinished(result):
            try checkResult(result, context: "finished deal")
        case let .gameOver(summary):
            try checkResult(summary.lastDeal, context: "game-over deal")
        default:
            break
        }
    }

    private static func checkScoreAgainstMatch(_ score: ScoreSheet, match: MatchSettings) throws {
        guard match.poolTarget != .max,
              match.poolClosure == .individualWithAmericanAid,
              match.poolTarget.isMultiple(of: score.players.count)
        else { return }

        let target = match.poolTarget / score.players.count
        if let player = score.players.first(where: { (score.pool[$0] ?? 0) > target }) {
            throw InvariantViolation(
                message: "individual pool entry exceeds its target: \(player) has \(score.pool[player] ?? 0), target \(target)"
            )
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

    /// The auction's derived fields are security-relevant recovery state, not
    /// disposable UI caches. In particular, `significantBidByPlayer` enforces
    /// the rule that misère may only be a player's first real bid. Derive and
    /// compare every redundant field against the recorded call history so a
    /// malformed host snapshot cannot reopen a bid that was already forfeited.
    private static func checkBiddingLedger(_ bidding: BiddingState) throws {
        let active = Set(bidding.activePlayers)
        try require(
            !bidding.passed.contains(bidding.currentPlayer),
            "bidding currentPlayer cannot already have passed"
        )

        var passedFromCalls: Set<PlayerID> = []
        var latestBidByPlayer: [PlayerID: ContractBid] = [:]
        var lastBid: (player: PlayerID, bid: ContractBid)?

        for record in bidding.calls {
            try require(
                active.contains(record.player),
                "auction call player \(record.player) ∉ activePlayers"
            )
            try require(
                !passedFromCalls.contains(record.player),
                "auction contains a call by \(record.player) after passing"
            )
            switch record.call {
            case .pass:
                passedFromCalls.insert(record.player)
            case let .bid(bid):
                latestBidByPlayer[record.player] = bid
                lastBid = (record.player, bid)
            }
        }

        try require(
            passedFromCalls == bidding.passed,
            "bidding passed set does not match auction calls"
        )
        try require(
            latestBidByPlayer == bidding.significantBidByPlayer,
            "bidding significant bid ledger does not match auction calls"
        )

        if let lastBid {
            try require(
                bidding.highestBid == lastBid.bid && bidding.highestBidder == lastBid.player,
                "bidding highest bid must match the last auction bid"
            )
        } else {
            try require(
                bidding.highestBid == nil && bidding.highestBidder == nil,
                "bidding without auction bids cannot carry a highest bid or bidder"
            )
        }
    }

    /// Defenders have both identity and order: forehand's successor speaks
    /// first, then the remaining defender. The whist reducer indexes this
    /// array directly, so set-only validation would still admit duplicates or
    /// reverse the legal speaking order after recovery.
    private static func checkDefendingSide(
        activePlayers: [PlayerID],
        declarer: PlayerID,
        defenders: [PlayerID],
        context: String
    ) throws {
        try require(
            activePlayers.contains(declarer),
            "\(context) declarer \(declarer) ∉ activePlayers"
        )
        try require(!defenders.contains(declarer), "\(context) declarer \(declarer) ∈ defenders")
        try require(defenders.count == 2, "\(context) defenders must be 2, got \(defenders.count)")

        guard let declarerIndex = activePlayers.firstIndex(of: declarer) else { return }
        let expected = (1..<activePlayers.count).map {
            activePlayers[(declarerIndex + $0) % activePlayers.count]
        }
        try require(
            defenders == expected,
            "\(context) defenders must be the ordered active seats excluding declarer; expected \(expected), got \(defenders)"
        )
    }

    /// An awaiting-whist snapshot can only be at one of three reducer-owned
    /// checkpoints: before the first call, before the second call, or at the
    /// first defender's response to a half-whist. Reject every other shape so
    /// recovery cannot skip or reorder a defensive decision.
    private static func checkWhistDecisionFlow(_ whist: WhistState) throws {
        let first = whist.defenders[0]
        let second = whist.defenders[1]

        switch whist.flow {
        case .normal:
            switch whist.calls.count {
            case 0:
                try require(
                    whist.currentPlayer == first,
                    "initial whist call must belong to first defender"
                )
            case 1:
                let call = whist.calls[0]
                try require(call.player == first, "first call must come from first defender")
                try require(call.call != .halfWhist, "first defender cannot open with half-whist")
                try require(
                    whist.currentPlayer == second,
                    "second whist call must belong to second defender"
                )
            default:
                throw InvariantViolation(message: "normal whist flow may contain at most one completed call")
            }

        case let .firstDefenderSecondChance(halfWhister):
            try require(halfWhister == second, "half-whister must be second defender")
            try require(whist.currentPlayer == first, "half-whist response must return to first defender")
            let expected = [
                WhistCallRecord(player: first, call: .pass),
                WhistCallRecord(player: second, call: .halfWhist),
            ]
            try require(
                whist.calls == expected,
                "half-whist second chance requires first pass followed by second defender half-whist"
            )
        }
    }

    /// Defender-mode selection exists only after exactly one defender whists
    /// and the other passes. Two whists start closed play immediately; two
    /// passes and half-whist branches score without entering this state.
    private static func checkDefenderModeFlow(_ mode: DefenderModeState) throws {
        let first = mode.defenders[0]
        let second = mode.defenders[1]
        try require(mode.whistCalls.count == 2, "defender mode requires exactly two whist calls")
        guard mode.whistCalls.count == 2 else { return }
        try require(
            mode.whistCalls.map(\.player) == [first, second],
            "defender mode whist calls must follow defender order"
        )

        let calls = mode.whistCalls.map(\.call)
        let expectedWhister: PlayerID
        switch calls {
        case [.whist, .pass]: expectedWhister = first
        case [.pass, .whist]: expectedWhister = second
        default:
            throw InvariantViolation(message: "defender mode requires exactly one whist and one pass")
        }
        try require(mode.whister == expectedWhister, "defender mode whister does not match whist calls")
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

    /// After exchange, the historical talon is retained for projections and
    /// replay, but both cards must still be traceable to the declarer's
    /// post-exchange hand, discard, or already-played cards. The full deck
    /// check alone cannot prove this because every standard card appears
    /// somewhere in the three hands plus discard.
    private static func checkExchangedTalon(
        _ talon: [Card],
        declarer: PlayerID,
        hands: [PlayerID: [Card]],
        discard: [Card],
        playedCards: [Card] = [],
        context: String
    ) throws {
        try require(talon.count == 2, "\(context) exchanged talon must contain 2 cards")
        try require(Set(talon).count == talon.count, "\(context) exchanged talon contains duplicate cards")
        let declarerCards = hands[declarer] ?? []
        let traceableCards = Set(declarerCards + discard + playedCards)
        try require(
            Set(talon).isSubset(of: traceableCards),
            "\(context) exchanged talon must remain with declarer hand, discard, or played cards"
        )
    }

    /// Replays every recorded card from reconstructed opening hands. A live
    /// reducer can only create this sequence one legal action at a time, but a
    /// recovered multiplayer snapshot crosses a trust boundary and must prove
    /// the same facts: seat order, lead ownership, follow-suit/trump duties,
    /// the recorded winner, and the next actor all derive from the cards.
    private static func checkPlayedHistory(_ playing: PlayingState) throws {
        let active = Set(playing.activePlayers)
        try require(
            playing.completedTricks.count < 10,
            "live playing state must contain fewer than 10 completed tricks"
        )
        try require(
            playing.currentTrick.count < playing.activePlayers.count,
            "playing current trick must be incomplete"
        )

        let recordedPlays = playing.completedTricks.flatMap(\.plays) + playing.currentTrick
        try require(
            recordedPlays.allSatisfy { active.contains($0.player) },
            "playing history contains a card played by a non-active seat"
        )

        var replayHands = playing.hands
        for play in recordedPlays {
            replayHands[play.player, default: []].append(play.card)
        }
        for player in playing.activePlayers {
            try require(
                replayHands[player]?.count == 10,
                "playing history must reconstruct a 10-card opening hand for \(player)"
            )
        }

        var expectedLeader = playing.isClassicFourPlayerAllPass
            ? playing.dealer
            : playing.activePlayers[0]
        var expectedPlayer = playing.activePlayers[0]

        for (index, trick) in playing.completedTricks.enumerated() {
            let expectedTalonLead: CardPlay? = playing.isClassicFourPlayerAllPass && index < 2
                ? CardPlay(player: playing.dealer, card: playing.talon[index])
                : nil
            try require(
                trick.talonLead == expectedTalonLead,
                "completed trick \(index + 1) has an invalid talon lead"
            )
            try require(
                trick.leader == expectedLeader,
                "completed trick \(index + 1) leader does not follow play history"
            )
            try require(
                trick.plays.count == playing.activePlayers.count,
                "completed trick \(index + 1) must contain one play per active seat"
            )

            let expectedPlayers = expectedPlayOrder(
                startingWith: expectedPlayer,
                activePlayers: playing.activePlayers,
                count: playing.activePlayers.count
            )
            try require(
                trick.plays.map(\.player) == expectedPlayers,
                "completed trick \(index + 1) play order does not follow seating order"
            )

            guard let firstPlay = trick.plays.first else { continue }
            let requiredSuit = playing.usesTalonLeads && index < 2
                ? playing.talon[index].suit
                : firstPlay.card.suit
            try require(
                trick.leadSuit == requiredSuit,
                "completed trick \(index + 1) records the wrong lead suit"
            )
            for play in trick.plays {
                try replay(
                    play,
                    requiredSuit: requiredSuit,
                    trump: playing.kind.trumpSuit,
                    hands: &replayHands,
                    context: "completed trick \(index + 1)"
                )
            }

            let table = (expectedTalonLead.map { [$0] } ?? []) + trick.plays
            let computedWinner = trickWinner(
                for: table,
                leadSuit: requiredSuit,
                trump: playing.kind.trumpSuit
            ).player
            try require(
                trick.winner == computedWinner,
                "completed trick \(index + 1) winner does not match its cards"
            )

            if playing.usesTalonLeads, index < 2 {
                expectedPlayer = playing.activePlayers[0]
                expectedLeader = playing.isClassicFourPlayerAllPass && index == 0
                    ? playing.dealer
                    : playing.activePlayers[0]
            } else {
                expectedPlayer = computedWinner
                expectedLeader = computedWinner
            }
        }

        try require(
            playing.leader == expectedLeader,
            "playing leader does not follow completed-trick history"
        )

        let currentPlayers = expectedPlayOrder(
            startingWith: expectedPlayer,
            activePlayers: playing.activePlayers,
            count: playing.currentTrick.count
        )
        try require(
            playing.currentTrick.map(\.player) == currentPlayers,
            "current trick play order does not follow seating order"
        )

        if let firstPlay = playing.currentTrick.first {
            let index = playing.completedTricks.count
            let requiredSuit = playing.usesTalonLeads && index < 2
                ? playing.talon[index].suit
                : firstPlay.card.suit
            for play in playing.currentTrick {
                try replay(
                    play,
                    requiredSuit: requiredSuit,
                    trump: playing.kind.trumpSuit,
                    hands: &replayHands,
                    context: "current trick"
                )
            }
        }

        let expectedCurrent = playing.currentTrick.last.map {
            playing.activePlayers.cyclicNext(after: $0.player)
        } ?? expectedPlayer
        try require(
            playing.currentPlayer == expectedCurrent,
            "playing currentPlayer does not follow card-play history"
        )
        try require(
            replayHands == playing.hands,
            "playing hands do not match the recorded card-play history"
        )
    }

    private static func expectedPlayOrder(
        startingWith first: PlayerID,
        activePlayers: [PlayerID],
        count: Int
    ) -> [PlayerID] {
        guard let start = activePlayers.firstIndex(of: first) else { return [] }
        return (0..<count).map { activePlayers[(start + $0) % activePlayers.count] }
    }

    private static func replay(
        _ play: CardPlay,
        requiredSuit: Suit,
        trump: Suit?,
        hands: inout [PlayerID: [Card]],
        context: String
    ) throws {
        guard var hand = hands[play.player], let cardIndex = hand.firstIndex(of: play.card) else {
            throw InvariantViolation(message: "\(context) card \(play.card) is absent from \(play.player)'s reconstructed hand")
        }

        if hand.contains(where: { $0.suit == requiredSuit }) {
            try require(
                play.card.suit == requiredSuit,
                "\(context) contains an illegal revoke by \(play.player)"
            )
        } else if let trump,
                  requiredSuit != trump,
                  hand.contains(where: { $0.suit == trump }) {
            try require(
                play.card.suit == trump,
                "\(context) requires \(play.player) to play trump"
            )
        }

        hand.remove(at: cardIndex)
        hands[play.player] = hand
    }

    private static func checkResult(_ result: DealResult, context: String) throws {
        try checkActiveSeats(result.activePlayers)
        let active = Set(result.activePlayers)
        let countPlayers = Set(result.trickCounts.keys)
        let scorePlayers = Set(result.scoreDelta.pool.keys)
        let hasFourPlayerRaspasyDealer = {
            guard case .allPass = result.kind else { return false }
            return scorePlayers.count == 4
                && countPlayers == scorePlayers
                && countPlayers.subtracting(active).count == 1
        }()
        try require(
            countPlayers == active || hasFourPlayerRaspasyDealer,
            "\(context) trickCounts keys \(sorted(result.trickCounts.keys)) do not match the deal's trick takers"
        )
        try require(
            result.trickCounts.values.allSatisfy { (0...10).contains($0) },
            "\(context) trick counts must stay between 0 and 10"
        )
        let trickTotal = result.trickCounts.values.reduce(0, +)
        switch result.kind {
        case .game, .misere, .allPass:
            try require(trickTotal == 10, "\(context) played trick total \(trickTotal), expected 10")
        case .passedOut, .withoutThree, .halfWhist:
            try require(trickTotal == 0, "\(context) unplayed trick total \(trickTotal), expected 0")
        }
        if result.settlement == nil {
            let completedTrickCounts = result.completedTricks.reduce(
                result.trickCounts.keys.dictionary(filledWith: 0)
            ) { counts, trick in
                var updated = counts
                updated[trick.winner, default: 0] += 1
                return updated
            }
            try require(
                result.trickCounts == completedTrickCounts,
                "\(context) trick counts must match completed-trick winners"
            )
        }
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
            settlement.finalTrickCounts.values.allSatisfy { (0...10).contains($0) },
            "\(context) final trick counts must stay between 0 and 10"
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
        dealsPlayed: Int,
        rules: PreferansRules,
        match: MatchSettings
    ) throws {
        try require(match.isPoolClosed(score), "gameOver summary requires a closed pulka")
        try require(summary.finalScore == score, "gameOver finalScore must match engine score")
        try require(summary.dealsPlayed == dealsPlayed, "gameOver dealsPlayed must match engine dealsPlayed")
        try checkResult(summary.lastDeal, context: "gameOver lastDeal")
        try summary.lastDeal.scoreDelta.validate(players: players)

        let standingsPlayers = summary.standings.map(\.player)
        try require(Set(standingsPlayers) == Set(players), "gameOver standings players must match players")
        try require(Set(standingsPlayers).count == standingsPlayers.count, "gameOver standings players must be unique")
        let balances = score.normalizedBalances(
            poolPointValue: Double(rules.poolPointWhistValue),
            mountainPointValue: Double(rules.mountainPointWhistValue)
        )
        for standing in summary.standings {
            try require(standing.pool == (score.pool[standing.player] ?? 0), "gameOver standing pool must match score")
            try require(standing.mountain == (score.mountain[standing.player] ?? 0), "gameOver standing mountain must match score")
            let expectedBalance = balances[standing.player] ?? 0
            try require(abs(standing.balance - expectedBalance) < 0.000_001, "gameOver standing balance must match score")
        }
    }

    /// Once a deal has been scored, the raspasy series counter is derived from
    /// that result: any ordinary contract or misère resets it, while an
    /// all-pass result may continue the series. Older snapshots did not carry
    /// the counter, so the all-pass branch deliberately remains permissive for
    /// a decoded zero; the upper-bound invariant above still prevents a
    /// fabricated streak from exceeding the number of scored deals.
    private static func checkRaspasySeriesCounter(
        _ kind: DealResultKind,
        consecutiveAllPassDeals: Int,
        context: String
    ) throws {
        guard kind != .allPass else { return }
        try require(
            consecutiveAllPassDeals == 0,
            "\(context) non-raspasy result must reset consecutiveAllPassDeals, got \(consecutiveAllPassDeals)"
        )
    }

    private static func sorted<S: Sequence>(_ ids: S) -> [String] where S.Element == PlayerID {
        ids.map(\.rawValue).sorted()
    }
}
