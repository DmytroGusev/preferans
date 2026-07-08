import XCTest
@testable import PreferansEngine

final class PreferansEngineTests: XCTestCase {
    func testContractOrderingPlacesMisereBetweenEightNoTrumpAndNineSpades() {
        let eightNoTrump = ContractBid.game(GameContract(8, .noTrump))
        let misere = ContractBid.misere
        let nineSpades = ContractBid.game(GameContract(9, .suit(.spades)))

        XCTAssertLessThan(eightNoTrump, misere)
        XCTAssertLessThan(misere, nineSpades)
    }

    func testDealUsesDealerRotationAndFourPlayerSitOut() throws {
        var engine = try PreferansEngine(players: ["north", "east", "south", "west"], firstDealer: "north")

        let events = try engine.startDeal(deck: Deck.standard32)

        XCTAssertEqual(events, [.dealStarted(dealer: "north", activePlayers: ["east", "south", "west"])])
        XCTAssertEqual(engine.nextDealer, "east")
        guard case let .bidding(bidding) = engine.state else {
            return XCTFail("Expected bidding state.")
        }
        XCTAssertNil(bidding.hands["north"])
        XCTAssertEqual(bidding.hands["east"]?.count, 10)
        XCTAssertEqual(bidding.talon.count, 2)
    }

    func testAllPassStartsAllPassPlay() throws {
        var engine = try PreferansEngine(players: ["north", "east", "south"], firstDealer: "north")
        try engine.startDeal(deck: Deck.standard32)

        _ = try engine.apply(.bid(player: "east", call: .pass))
        _ = try engine.apply(.bid(player: "south", call: .pass))
        let events = try engine.apply(.bid(player: "north", call: .pass))

        XCTAssertTrue(events.contains(.allPassed))
        guard case let .playing(playing) = engine.state,
              case .allPass = playing.kind else {
            return XCTFail("Expected all-pass play.")
        }
        XCTAssertEqual(playing.currentPlayer, "east")
    }

    func testAllPassLeadStartsWithForehandForThreeAndFourPlayerTables() throws {
        struct TableCase {
            let players: [PlayerID]
            let dealer: PlayerID
            let expectedActive: [PlayerID]
        }

        let cases = [
            TableCase(
                players: ["north", "east", "south"],
                dealer: "north",
                expectedActive: ["east", "south", "north"]
            ),
            TableCase(
                players: ["north", "east", "south", "west"],
                dealer: "north",
                expectedActive: ["east", "south", "west"]
            ),
        ]

        for table in cases {
            var engine = try PreferansEngine(players: table.players, firstDealer: table.dealer)
            try engine.startDeal(deck: Deck.standard32)
            for player in table.expectedActive {
                try engine.apply(.bid(player: player, call: .pass))
            }

            guard case let .playing(playing) = engine.state,
                  case .allPass = playing.kind else {
                return XCTFail("Three passes must start all-pass play.")
            }
            XCTAssertEqual(playing.activePlayers, table.expectedActive)
            XCTAssertEqual(playing.leader, table.expectedActive[0])
            XCTAssertEqual(playing.currentPlayer, table.expectedActive[0])
            XCTAssertEqual(playing.leader, engine.activePlayers(forDealer: table.dealer)[0],
                           "Forehand, immediately after the dealer, opens an all-pass deal.")
        }
    }

    func testTenTrickContractWithRequiredWhistDoesNotSkipDefenders() throws {
        let players: [PlayerID] = ["north", "east", "south"]
        var engine = try PreferansEngine(
            players: players,
            rules: .leningrad,
            firstDealer: "south"
        )
        try engine.startDeal(deck: Deck.standard32)

        let contract = GameContract(10, .suit(.clubs))
        try engine.apply(.bid(player: "north", call: .bid(.game(contract))))
        try engine.apply(.bid(player: "east", call: .pass))
        try engine.apply(.bid(player: "south", call: .pass))

        guard case let .awaitingDiscard(exchange) = engine.state else {
            return XCTFail("Expected the declarer to receive the talon.")
        }
        try engine.apply(.discard(player: "north", cards: exchange.talon))
        try engine.apply(.declareContract(player: "north", contract: contract))

        guard case let .awaitingWhist(whist) = engine.state else {
            return XCTFail("Required-whist ten must enter the defenders' decision phase.")
        }
        XCTAssertEqual(whist.currentPlayer, "east")
        XCTAssertEqual(engine.legalWhistCalls(for: "east"), [.whist])
        try engine.apply(.whist(player: "east", call: .whist))
        XCTAssertEqual(engine.legalWhistCalls(for: "south"), [.whist])
        try engine.apply(.whist(player: "south", call: .whist))

        guard case let .playing(playing) = engine.state,
              case let .game(context) = playing.kind else {
            return XCTFail("Expected play after both forced whists.")
        }
        XCTAssertEqual(context.whisters, ["east", "south"])
    }

    func testLeningradScoringDoublesContractAndSplitsGentlemanWhist() {
        let players: [PlayerID] = ["north", "east", "south"]
        let deal = DealDeckLayout.deal(deck: Deck.standard32, activePlayers: players)
        let contract = GameContract(6, .suit(.clubs))
        let playing = PlayingState(
            dealer: "south",
            activePlayers: players,
            hands: deal.hands,
            talon: deal.talon,
            discard: deal.talon,
            leader: "north",
            currentPlayer: "north",
            trickCounts: ["north": 4, "east": 4, "south": 2],
            kind: .game(GamePlayContext(
                declarer: "north",
                contract: contract,
                defenders: ["east", "south"],
                whisters: ["east"],
                defenderPlayMode: .open,
                whistCalls: []
            ))
        )

        let result = PreferansScoring(
            players: players,
            rules: .leningrad,
            match: .unbounded
        ).completedPlay(playing)

        // 6-game is worth 4 in Leningrad. North is two short: 8 mountain.
        // The lone whister and the passer share 6 defender tricks (24) and
        // two undertricks of consolation (8): 16 whists each.
        XCTAssertEqual(result.scoreDelta.mountain["north"], 8)
        XCTAssertEqual(result.scoreDelta.whists["east"]?["north"], 16)
        XCTAssertEqual(result.scoreDelta.whists["south"]?["north"], 16)
    }

    func testHalfWhistRequiresFirstDefenderSecondChanceAndScores() throws {
        var engine = try PreferansEngine(players: ["north", "east", "south"], firstDealer: "north")
        try engine.startDeal(deck: Deck.standard32)
        let initialHands = try initialHands(in: engine)

        _ = try engine.apply(.bid(player: "east", call: .bid(.game(GameContract(6, .suit(.clubs))))))
        _ = try engine.apply(.bid(player: "south", call: .pass))
        _ = try engine.apply(.bid(player: "north", call: .pass))

        guard case let .awaitingDiscard(exchange) = engine.state else {
            return XCTFail("Expected discard.")
        }
        let discard = Array(((exchange.hands["east"] ?? []) + exchange.talon).prefix(2))
        _ = try engine.apply(.discard(player: "east", cards: discard))
        _ = try engine.apply(.declareContract(player: "east", contract: GameContract(6, .suit(.clubs))))

        _ = try engine.apply(.whist(player: "south", call: .pass))
        _ = try engine.apply(.whist(player: "north", call: .halfWhist))
        guard case let .awaitingWhist(whist) = engine.state,
              whist.currentPlayer == "south" else {
            return XCTFail("Expected first defender second chance.")
        }

        let events = try engine.apply(.whist(player: "south", call: .pass))

        guard case let .dealFinished(result) = engine.state,
              case let .halfWhist(declarer, contract, halfWhister) = result.kind else {
            return XCTFail("Expected half-whist result.")
        }
        XCTAssertEqual(declarer, "east")
        XCTAssertEqual(contract, GameContract(6, .suit(.clubs)))
        XCTAssertEqual(halfWhister, "north")
        XCTAssertTrue(events.contains { if case .dealScored = $0 { return true }; return false })
        XCTAssertEqual(engine.score.pool["east"], 2)
        XCTAssertEqual(engine.score.whistsWritten(by: "north", on: "east"), 4)
        XCTAssertEqual(result.initialHands, initialHands)
    }

    func testFirstDefenderMayRevokePassByWhistingOverHalfWhist() throws {
        var engine = try PreferansEngine(players: ["north", "east", "south"], firstDealer: "north")
        try engine.startDeal(deck: Deck.standard32)

        _ = try engine.apply(.bid(player: "east", call: .bid(.game(GameContract(6, .suit(.clubs))))))
        _ = try engine.apply(.bid(player: "south", call: .pass))
        _ = try engine.apply(.bid(player: "north", call: .pass))
        try EngineTestDriver.discardTalon(engine: &engine, declarer: "east")
        _ = try engine.apply(.declareContract(player: "east", contract: GameContract(6, .suit(.clubs))))

        _ = try engine.apply(.whist(player: "south", call: .pass))
        _ = try engine.apply(.whist(player: "north", call: .halfWhist))
        guard case let .awaitingWhist(secondChance) = engine.state,
              secondChance.currentPlayer == "south",
              case .firstDefenderSecondChance(halfWhister: "north") = secondChance.flow else {
            return XCTFail("Expected first defender second chance; got \(engine.state.description).")
        }

        // South revokes the earlier pass by whisting over north's half-whist.
        let events = try engine.apply(.whist(player: "south", call: .whist))

        XCTAssertTrue(events.contains { if case .playStarted = $0 { return true }; return false })
        guard case let .playing(playing) = engine.state,
              case let .game(context) = playing.kind else {
            return XCTFail("Expected closed game play; got \(engine.state.description).")
        }
        // Play starts with both defenders whisting: the revoking first
        // defender, then the half-whister.
        XCTAssertEqual(context.whisters, ["south", "north"])
        XCTAssertEqual(context.defenderPlayMode, .closed)

        try EngineTestDriver.playOut(engine: &engine, policy: .lowestLegal)
        guard case let .dealFinished(result) = engine.state,
              case let .game(declarer, contract, whisters) = result.kind else {
            return XCTFail("Expected dealFinished.game; got \(engine.state.description).")
        }
        XCTAssertEqual(declarer, "east")
        XCTAssertEqual(contract, GameContract(6, .suit(.clubs)))
        XCTAssertEqual(whisters, ["south", "north"])
        // Deterministic lowest-legal play of the unshuffled standard deck:
        // east (trump clubs) takes only 3 of the 6 contracted tricks.
        XCTAssertEqual(result.trickCounts, ["east": 3, "south": 1, "north": 6])
        // Failed by 3 undertricks: no pool, east mountains value 2 * 3 = 6.
        XCTAssertEqual(engine.score.pool["east"], 0)
        XCTAssertEqual(engine.score.mountain["east"], 6)
        // Each whister writes consolation 2 * 3 = 6 plus their own tricks:
        // south 6 + 2 * 1 = 8, north 6 + 2 * 6 = 18.
        XCTAssertEqual(engine.score.whistsWritten(by: "south", on: "east"), 8)
        XCTAssertEqual(engine.score.whistsWritten(by: "north", on: "east"), 18)
        // Responsible whist quota for a 6-contract is 4, split 2 per
        // whister: north met it (6 tricks); south took 1 of 2, mountaining
        // 1 missing * value 2 = 2.
        XCTAssertEqual(engine.score.mountain["south"], 2)
        XCTAssertEqual(engine.score.mountain["north"], 0)
    }

    func testSeniorHandMayHoldEqualBidAndJuniorMustRaise() throws {
        var engine = try PreferansEngine(players: ["north", "east", "south"], firstDealer: "north")
        try engine.startDeal(deck: Deck.standard32)

        // Rotation for dealer north is [east, south, north]; east is senior.
        _ = try engine.apply(.bid(player: "east", call: .bid(.game(GameContract(6, .suit(.clubs))))))
        _ = try engine.apply(.bid(player: "south", call: .bid(.game(GameContract(6, .suit(.diamonds))))))
        _ = try engine.apply(.bid(player: "north", call: .pass))

        // Two live bidders remain and south holds the highest bid (6♦);
        // the senior hand (east) may hold at the same level.
        let holdBid = BidCall.bid(.game(GameContract(6, .suit(.diamonds))))
        XCTAssertTrue(engine.legalBidCalls(for: "east").contains(holdBid),
                      "Senior hand must be offered the equal-bid hold.")
        _ = try engine.apply(.bid(player: "east", call: holdBid))

        // The junior hand may never hold — it must raise or pass.
        let southCalls = engine.legalBidCalls(for: "south")
        XCTAssertFalse(southCalls.contains(holdBid),
                       "Junior hand must not be offered the equal-bid hold.")
        XCTAssertTrue(southCalls.contains(.bid(.game(GameContract(6, .suit(.hearts))))))
        XCTAssertTrue(southCalls.contains(.pass))
        XCTAssertThrowsError(try engine.apply(.bid(player: "south", call: holdBid)))

        let events = try engine.apply(.bid(player: "south", call: .pass))
        XCTAssertTrue(events.contains(.auctionWon(declarer: "east", bid: .game(GameContract(6, .suit(.diamonds))))))
    }

    func testHoldBidDisabledForcesSeniorHandToRaiseOrPass() throws {
        var engine = try PreferansEngine(
            players: ["north", "east", "south"],
            rules: PreferansRules(allowSeniorHandHoldBid: false),
            firstDealer: "north"
        )
        try engine.startDeal(deck: Deck.standard32)

        _ = try engine.apply(.bid(player: "east", call: .bid(.game(GameContract(6, .suit(.clubs))))))
        _ = try engine.apply(.bid(player: "south", call: .bid(.game(GameContract(6, .suit(.diamonds))))))
        _ = try engine.apply(.bid(player: "north", call: .pass))

        // With the hold rule off, even the senior hand cannot repeat the
        // highest bid — only a raise or a pass is on offer.
        let holdBid = BidCall.bid(.game(GameContract(6, .suit(.diamonds))))
        let eastCalls = engine.legalBidCalls(for: "east")
        XCTAssertFalse(eastCalls.contains(holdBid),
                       "allowSeniorHandHoldBid: false must remove the equal-bid hold.")
        XCTAssertTrue(eastCalls.contains(.bid(.game(GameContract(6, .suit(.hearts))))))
        XCTAssertTrue(eastCalls.contains(.pass))
        XCTAssertThrowsError(try engine.apply(.bid(player: "east", call: holdBid)))
    }

    func testTenTrickContractSkipsWhistByDefault() throws {
        var engine = try PreferansEngine(players: ["north", "east", "south"], firstDealer: "north")
        try engine.startDeal(deck: Deck.standard32)
        try driveToTenTrickDeclaration(engine: &engine)

        _ = try engine.apply(.declareContract(player: "east", contract: GameContract(10, .suit(.spades))))

        guard case let .playing(playing) = engine.state,
              case let .game(context) = playing.kind else {
            return XCTFail("Expected play to start immediately, got \(engine.state.description).")
        }
        XCTAssertTrue(context.whisters.isEmpty, "Default rules play a 10-trick contract unwhisted.")
    }

    func testTenTrickContractForcesBothDefendersToWhistWhenRuleIsOn() throws {
        var engine = try PreferansEngine(
            players: ["north", "east", "south"],
            rules: PreferansRules(requireWhistOnTenTrickContracts: true),
            firstDealer: "north"
        )
        try engine.startDeal(deck: Deck.standard32)
        try driveToTenTrickDeclaration(engine: &engine)

        _ = try engine.apply(.declareContract(player: "east", contract: GameContract(10, .suit(.spades))))

        // The rule routes the ten-game through the whist phase, and whisting
        // is mandatory: passing (and half-whist) are not offered.
        guard case .awaitingWhist = engine.state else {
            return XCTFail("Expected the whist phase, got \(engine.state.description).")
        }
        XCTAssertEqual(engine.legalWhistCalls(for: "south"), [.whist])
        _ = try engine.apply(.whist(player: "south", call: .whist))
        XCTAssertEqual(engine.legalWhistCalls(for: "north"), [.whist])
        XCTAssertThrowsError(try engine.apply(.whist(player: "north", call: .pass)))
        _ = try engine.apply(.whist(player: "north", call: .whist))

        guard case let .playing(playing) = engine.state,
              case let .game(context) = playing.kind else {
            return XCTFail("Expected play after forced whists, got \(engine.state.description).")
        }
        XCTAssertEqual(context.whisters, ["south", "north"])
    }

    func testTotusPolicyRequireWhistForcesWhistWithoutRulesFlag() throws {
        var engine = try PreferansEngine(
            players: ["north", "east", "south"],
            rules: .sochi,
            match: MatchSettings(totus: .asTenTrickGame(requireWhist: true)),
            firstDealer: "north"
        )
        try engine.startDeal(deck: Deck.standard32)
        try driveToTenTrickDeclaration(engine: &engine)

        _ = try engine.apply(.declareContract(player: "east", contract: GameContract(10, .suit(.spades))))

        guard case .awaitingWhist = engine.state else {
            return XCTFail("The totus policy alone must force the whist phase, got \(engine.state.description).")
        }
    }

    /// Auction: east wins with a 10♠ bid, then discards, leaving the engine
    /// at the contract declaration for a ten-trick game.
    private func driveToTenTrickDeclaration(engine: inout PreferansEngine) throws {
        _ = try engine.apply(.bid(player: "east", call: .bid(.game(GameContract(10, .suit(.spades))))))
        _ = try engine.apply(.bid(player: "south", call: .pass))
        _ = try engine.apply(.bid(player: "north", call: .pass))
        guard case let .awaitingDiscard(exchange) = engine.state else {
            throw EngineTestError("Expected discard, got \(engine.state.description).")
        }
        let discard = Array(((exchange.hands["east"] ?? []) + exchange.talon).prefix(2))
        _ = try engine.apply(.discard(player: "east", cards: discard))
    }

    func testDeclarerCanConcedeWithoutThreeBeforeNamingContract() throws {
        var engine = try PreferansEngine(players: ["north", "east", "south"], firstDealer: "north")
        try engine.startDeal(deck: Deck.standard32)
        let initialHands = try initialHands(in: engine)

        _ = try engine.apply(.bid(player: "east", call: .bid(.game(GameContract(6, .suit(.clubs))))))
        _ = try engine.apply(.bid(player: "south", call: .pass))
        _ = try engine.apply(.bid(player: "north", call: .pass))

        guard case let .awaitingDiscard(exchange) = engine.state else {
            return XCTFail("Expected discard.")
        }
        let discard = Array(((exchange.hands["east"] ?? []) + exchange.talon).prefix(2))
        _ = try engine.apply(.discard(player: "east", cards: discard))

        let events = try engine.apply(.concedeWithoutThree(player: "east"))

        XCTAssertTrue(events.contains(.contractConcededWithoutThree(
            declarer: "east",
            bid: .game(GameContract(6, .suit(.clubs)))
        )))
        guard case let .dealFinished(result) = engine.state,
              case let .withoutThree(declarer, bid) = result.kind else {
            return XCTFail("Expected without-three result.")
        }
        XCTAssertEqual(declarer, "east")
        XCTAssertEqual(bid, .game(GameContract(6, .suit(.clubs))))
        XCTAssertEqual(engine.score.mountain["east"], GameContract(6, .suit(.clubs)).value * 3)
        XCTAssertEqual(engine.score.pool["east"], 0)
        XCTAssertEqual(engine.score.whistsWritten(by: "north", on: "east"), 0)
        XCTAssertEqual(engine.score.whistsWritten(by: "south", on: "east"), 0)
        XCTAssertEqual(result.trickCounts, ["north": 0, "east": 0, "south": 0])
        XCTAssertEqual(result.completedTricks, [])
        XCTAssertEqual(result.initialHands, initialHands)
    }

    func testConcedeWithoutThreeIsRejectedForMisere() throws {
        // Misère never reaches awaitingContract through normal play (the
        // exchange reducer routes it straight to playing), so rehydrate the
        // defensive state from a snapshot to pin the reducer's guard.
        let activePlayers: [PlayerID] = ["east", "south", "north"]
        let deal = DealDeckLayout.deal(deck: Deck.standard32, activePlayers: activePlayers)
        let declaration = ContractDeclarationState(
            dealer: "north",
            activePlayers: activePlayers,
            hands: deal.hands,
            talon: deal.talon,
            // Declarer kept the dealt ten and dropped the talon.
            discard: deal.talon,
            declarer: "east",
            finalBid: .misere,
            auction: []
        )
        let snapshot = PreferansSnapshot(
            players: ["north", "east", "south"],
            rules: .sochi,
            state: .awaitingContract(declaration),
            score: ScoreSheet(players: ["north", "east", "south"]),
            nextDealer: "east"
        )
        var engine = try PreferansEngine(snapshot: snapshot)

        XCTAssertThrowsError(try engine.apply(.concedeWithoutThree(player: "east"))) { error in
            guard case PreferansError.invalidContract = error else {
                return XCTFail("Expected invalidContract; got \(error).")
            }
        }
        guard case .awaitingContract = engine.state else {
            return XCTFail("Rejected concession must not change state; got \(engine.state.description).")
        }
    }

    func testWithoutThreeInFourPlayerDealScoresDeclarerTripleAndDealerNothing() throws {
        var engine = try PreferansEngine(players: ["north", "east", "south", "west"], firstDealer: "north")
        try engine.startDeal(deck: Deck.standard32)

        // North deals and sits out; rotation is [east, south, west].
        try EngineTestDriver.driveAuctionWinning(
            engine: &engine,
            declarer: "east",
            bid: .game(GameContract(6, .suit(.clubs)))
        )
        try EngineTestDriver.discardTalon(engine: &engine, declarer: "east")

        _ = try engine.apply(.concedeWithoutThree(player: "east"))

        guard case let .dealFinished(result) = engine.state,
              case let .withoutThree(declarer, bid) = result.kind else {
            return XCTFail("Expected without-three result; got \(engine.state.description).")
        }
        XCTAssertEqual(declarer, "east")
        XCTAssertEqual(bid, .game(GameContract(6, .suit(.clubs))))
        XCTAssertEqual(result.activePlayers, ["east", "south", "west"])
        // Declarer mountains bid value * 3 = 2 * 3 = 6; everyone else —
        // including the sitting-out dealer — writes nothing.
        XCTAssertEqual(engine.score.mountain, ["north": 0, "east": 6, "south": 0, "west": 0])
        XCTAssertEqual(engine.score.pool, ["north": 0, "east": 0, "south": 0, "west": 0])
        XCTAssertEqual(result.scoreDelta.mountain, ["north": 0, "east": 6, "south": 0, "west": 0])
        XCTAssertEqual(engine.score.whistsWritten(by: "north", on: "east"), 0)
        XCTAssertEqual(engine.score.whistsWritten(by: "south", on: "east"), 0)
        XCTAssertEqual(engine.score.whistsWritten(by: "west", on: "east"), 0)
    }

    func testDealResultKeepsOpeningHandsAfterDeclarerKeepsPrikupCards() throws {
        var engine = try PreferansEngine(players: ["north", "east", "south"], firstDealer: "north")
        try engine.startDeal(deck: Deck.standard32)
        let initialHands = try initialHands(in: engine)

        try EngineTestDriver.driveAuctionWinning(
            engine: &engine,
            declarer: "east",
            bid: .game(GameContract(6, .suit(.clubs)))
        )
        guard case let .awaitingDiscard(exchange) = engine.state,
              let eastHand = exchange.hands["east"] else {
            return XCTFail("Expected east to choose discards.")
        }
        _ = try engine.apply(.discard(player: "east", cards: Array(eastHand.prefix(2))))
        _ = try engine.apply(.declareContract(player: "east", contract: GameContract(6, .suit(.clubs))))
        try EngineTestDriver.forceWhist(engine: &engine)
        try EngineTestDriver.playOut(engine: &engine, policy: .lowestLegal)

        guard case let .dealFinished(result) = engine.state else {
            return XCTFail("Expected scored deal; got \(engine.state.description).")
        }
        XCTAssertEqual(result.initialHands, initialHands)
    }

    func testStalingradSixSpadesForcesClosedWhistFromBothDefenders() throws {
        var engine = try PreferansEngine(players: ["north", "east", "south"], firstDealer: "north")
        try engine.startDeal(deck: Deck.standard32)

        _ = try engine.apply(.bid(player: "east", call: .bid(.game(GameContract(6, .suit(.spades))))))
        _ = try engine.apply(.bid(player: "south", call: .pass))
        _ = try engine.apply(.bid(player: "north", call: .pass))

        guard case let .awaitingDiscard(exchange) = engine.state else {
            return XCTFail("Expected discard.")
        }
        let discard = Array(((exchange.hands["east"] ?? []) + exchange.talon).prefix(2))
        _ = try engine.apply(.discard(player: "east", cards: discard))
        _ = try engine.apply(.declareContract(player: "east", contract: GameContract(6, .suit(.spades))))

        XCTAssertEqual(engine.legalWhistCalls(for: "south"), [.whist])
        XCTAssertThrowsError(try engine.apply(.whist(player: "south", call: .pass)))

        _ = try engine.apply(.whist(player: "south", call: .whist))
        XCTAssertEqual(engine.legalWhistCalls(for: "north"), [.whist])
        let events = try engine.apply(.whist(player: "north", call: .whist))

        XCTAssertTrue(events.contains { if case .playStarted = $0 { return true }; return false })
        guard case let .playing(playing) = engine.state,
              case let .game(context) = playing.kind else {
            return XCTFail("Expected closed game play.")
        }
        XCTAssertEqual(context.contract, GameContract(6, .suit(.spades)))
        XCTAssertEqual(context.whisters, ["south", "north"])
        XCTAssertEqual(context.defenderPlayMode, .closed)
    }

    func testSnapshotAndActionsAreCodable() throws {
        var engine = try PreferansEngine(players: ["north", "east", "south"])
        try engine.startDeal(deck: Deck.standard32)

        let encodedSnapshot = try JSONEncoder().encode(engine.snapshot)
        let decodedSnapshot = try JSONDecoder().decode(PreferansSnapshot.self, from: encodedSnapshot)
        let restored = try PreferansEngine(snapshot: decodedSnapshot)

        XCTAssertEqual(restored.snapshot, engine.snapshot)

        let actions: [PreferansAction] = [
            .bid(player: "east", call: .pass),
            .concedeWithoutThree(player: "east"),
        ]
        for action in actions {
            let encodedAction = try JSONEncoder().encode(action)
            XCTAssertEqual(try JSONDecoder().decode(PreferansAction.self, from: encodedAction), action)
        }
    }

    private func initialHands(in engine: PreferansEngine) throws -> [PlayerID: [Card]] {
        guard case let .bidding(bidding) = engine.state else {
            throw EngineTestError("Expected bidding state; got \(engine.state.description).")
        }
        return bidding.hands.mapValues { $0.sorted() }
    }
}
