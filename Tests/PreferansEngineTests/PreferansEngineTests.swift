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

        let action = PreferansAction.bid(player: "east", call: .pass)
        let encodedAction = try JSONEncoder().encode(action)
        XCTAssertEqual(try JSONDecoder().decode(PreferansAction.self, from: encodedAction), action)
    }

    private func initialHands(in engine: PreferansEngine) throws -> [PlayerID: [Card]] {
        guard case let .bidding(bidding) = engine.state else {
            throw EngineTestError("Expected bidding state; got \(engine.state.description).")
        }
        return bidding.hands.mapValues { $0.sorted() }
    }
}
