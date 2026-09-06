import XCTest
@testable import PreferansEngine
@testable import PreferansEngineTestSupport

/// Engine-level tests for ``MatchSettings``: pool-target game-over transition,
/// dedicated totus auction → declaration → bonus, and the legal-bid gating
/// that switches between the standard 10-trick ladder and the totus bid.
final class MatchSettingsTests: XCTestCase {
    // MARK: - Helpers

    private static let northSpadesSixDeck: [Card] = {
        // Same shape as the test harness scenario but constructed inline so
        // engine tests stay decoupled from the app target.
        let north: [Card] = [
            Card(.spades, .ace), Card(.spades, .king),
            Card(.spades, .queen), Card(.spades, .jack),
            Card(.spades, .ten), Card(.spades, .nine),
            Card(.clubs, .ace), Card(.clubs, .king),
            Card(.diamonds, .ace), Card(.hearts, .ace)
        ]
        let east: [Card] = [
            Card(.spades, .eight), Card(.spades, .seven),
            Card(.clubs, .queen), Card(.clubs, .jack),
            Card(.hearts, .king), Card(.hearts, .queen),
            Card(.diamonds, .king), Card(.diamonds, .queen),
            Card(.hearts, .seven), Card(.diamonds, .seven)
        ]
        let south: [Card] = [
            Card(.clubs, .ten), Card(.clubs, .nine),
            Card(.clubs, .eight), Card(.clubs, .seven),
            Card(.hearts, .jack), Card(.hearts, .ten),
            Card(.hearts, .nine), Card(.hearts, .eight),
            Card(.diamonds, .ten), Card(.diamonds, .eight)
        ]
        let talon: [Card] = [Card(.diamonds, .jack), Card(.diamonds, .nine)]
        return DealDeckLayout.deck(north: north, east: east, south: south, talon: talon)
    }()

    private func makeEngine(
        players: [PlayerID] = ["north", "east", "south"],
        rules: PreferansRules = .sochi,
        match: MatchSettings = .unbounded,
        firstDealer: PlayerID = "south"
    ) throws -> PreferansEngine {
        try PreferansEngine(players: players, rules: rules, match: match, firstDealer: firstDealer)
    }

    private func startDeal(_ engine: inout PreferansEngine, deck: [Card]? = nil) throws {
        try engine.startDeal(deck: deck ?? Self.northSpadesSixDeck)
    }

    private static let sixClubs = ContractBid.game(GameContract(6, .suit(.clubs)))

    // Drives auction up to passed-out. North wins 6♣, both defenders pass on
    // whist, declarer is credited contract value (2 pool) and the deal closes
    // without playing tricks. Returns events from the final whist call.
    @discardableResult
    private func runPassedOutSixClubs(_ engine: inout PreferansEngine) throws -> [PreferansEvent] {
        try engine.startDeal(deck: Self.northSpadesSixDeck)
        _ = try engine.apply(.bid(player: "north", call: .bid(Self.sixClubs)))
        _ = try engine.apply(.bid(player: "east", call: .pass))
        _ = try engine.apply(.bid(player: "south", call: .pass))
        guard case let .awaitingDiscard(exchange) = engine.state else {
            XCTFail("Expected awaitingDiscard")
            return []
        }
        _ = try engine.apply(.discard(player: "north", cards: exchange.talon))
        _ = try engine.apply(.declareContract(player: "north", contract: GameContract(6, .suit(.clubs))))
        _ = try engine.apply(.whist(player: "east", call: .pass))
        return try engine.apply(.whist(player: "south", call: .pass))
    }

    // MARK: - Pool target → gameOver

    func testUnboundedWireEncodingAvoidsJavaScriptIntegerOverflow() throws {
        let data = try JSONEncoder().encode(MatchSettings.unbounded)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["poolTarget"])
        XCTAssertEqual(try JSONDecoder().decode(MatchSettings.self, from: data), .unbounded)
    }

    func testUnboundedMatchNeverFiresGameOver() throws {
        var engine = try makeEngine()
        let events = try runPassedOutSixClubs(&engine)

        XCTAssertFalse(events.contains { if case .matchEnded = $0 { return true } else { return false } })
        guard case .dealFinished = engine.state else {
            return XCTFail("Default match should land in dealFinished, not gameOver. Got \(engine.state.description).")
        }
        XCTAssertEqual(engine.score.pool["north"], 2)
        XCTAssertEqual(engine.dealsPlayed, 1)
    }

    func testIndividualClosureRejectsATargetThatCannotDivideAcrossSeats() {
        XCTAssertThrowsError(
            try makeEngine(match: MatchSettings(poolTarget: 10))
        ) { error in
            guard case let PreferansError.invalidMatch(message) = error else {
                return XCTFail("Expected invalidMatch; got \(error)")
            }
            XCTAssertTrue(message.contains("divide evenly"))
        }
    }

    func testEngineRejectsNegativeDedicatedTotusBonus() {
        let settings = MatchSettings(
            poolTarget: .max,
            totus: .dedicatedContract(requireWhist: true, bonusPool: -1)
        )

        XCTAssertThrowsError(try makeEngine(match: settings)) { error in
            guard case let PreferansError.invalidMatch(message) = error else {
                return XCTFail("Expected invalidMatch; got \(error)")
            }
            XCTAssertTrue(message.contains("bonus pool cannot be negative"))
        }
    }

    func testDecodingRejectsNegativeDedicatedTotusBonus() throws {
        let settings = MatchSettings(
            poolTarget: .max,
            totus: .dedicatedContract(requireWhist: true, bonusPool: -1)
        )
        let encoded = try JSONEncoder().encode(settings)

        XCTAssertThrowsError(try JSONDecoder().decode(MatchSettings.self, from: encoded)) { error in
            guard case let DecodingError.dataCorrupted(context) = error else {
                return XCTFail("Expected dataCorrupted; got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("bonus pool cannot be negative"))
        }
    }

    func testGameOverFiresWhenPoolSumCrossesTargetExactly() throws {
        var engine = try makeEngine(match: MatchSettings(poolTarget: 2, poolClosure: .tableTotal))
        let events = try runPassedOutSixClubs(&engine)

        XCTAssertTrue(events.contains { if case .matchEnded = $0 { return true } else { return false } },
                      "matchEnded event must accompany the deal that crosses the target")
        guard case let .gameOver(summary) = engine.state else {
            return XCTFail("Expected gameOver; got \(engine.state.description).")
        }
        XCTAssertEqual(summary.dealsPlayed, 1)
        XCTAssertEqual(summary.finalScore.pool["north"], 2)
        XCTAssertEqual(summary.standings.first?.player, "north",
                       "north should top the standings after winning the contract")
    }

    func testGameOverDoesNotFireWhenPoolStaysBelowTarget() throws {
        var engine = try makeEngine(match: MatchSettings(poolTarget: 10, poolClosure: .tableTotal))
        _ = try runPassedOutSixClubs(&engine)

        guard case .dealFinished = engine.state else {
            return XCTFail("Pool sum 2 < target 10 should keep the engine open.")
        }
        XCTAssertEqual(engine.dealsPlayed, 1)
    }

    func testStartDealFromGameOverThrows() throws {
        var engine = try makeEngine(match: MatchSettings(poolTarget: 2, poolClosure: .tableTotal))
        _ = try runPassedOutSixClubs(&engine)
        guard case .gameOver = engine.state else {
            return XCTFail("Setup did not reach gameOver.")
        }

        XCTAssertThrowsError(try engine.startDeal(deck: Self.northSpadesSixDeck)) { error in
            guard case let PreferansError.invalidState(_, actual) = error else {
                return XCTFail("Expected invalidState; got \(error)")
            }
            XCTAssertTrue(actual.contains("gameOver"), "Error should mention gameOver state")
        }
    }

    func testMatchSummaryStandingsAreSortedByBalanceWithDeterministicTiebreak() throws {
        var engine = try makeEngine(match: MatchSettings(poolTarget: 2, poolClosure: .tableTotal))
        _ = try runPassedOutSixClubs(&engine)

        guard case let .gameOver(summary) = engine.state else {
            return XCTFail("Expected gameOver.")
        }
        // Balance is normalized — average is subtracted. North (+2 pool, 20
        // raw) is highest; east and south at 0 raw tie below average.
        XCTAssertEqual(summary.standings.map(\.player), ["north", "east", "south"])
        XCTAssertGreaterThan(summary.standings[0].balance, summary.standings[1].balance)
        // Tiebreak between east/south falls back to seat order in `players`.
        XCTAssertEqual(summary.standings[1].player, "east")
        XCTAssertEqual(summary.standings[2].player, "south")
    }

    // MARK: - Multi-deal raspasy

    func testRaspasyProgressionsExposeSupportedPriceAndExitStages() {
        XCTAssertEqual(
            [0, 1, 2, 3].map { RaspasyPolicy.sochi.scoreMultiplier(precededBy: $0) },
            [1, 2, 3, 3]
        )
        XCTAssertEqual(
            [0, 1, 2, 3].map { RaspasyPolicy.sochi.minimumGameTricks(after: $0) },
            [6, 7, 8, 8]
        )

        let geometric = RaspasyPolicy.progressive(penalties: .geometric, exit: .constrained)
        XCTAssertEqual(
            [0, 1, 2, 3].map { geometric.scoreMultiplier(precededBy: $0) },
            [1, 2, 4, 4]
        )
        XCTAssertEqual(
            [0, 1, 2, 3].map { geometric.minimumGameTricks(after: $0) },
            [6, 7, 7, 7]
        )

        let cappedDouble = RaspasyPolicy.progressive(penalties: .cappedDouble, exit: .simple)
        XCTAssertEqual(
            [0, 1, 2, 3].map { cappedDouble.scoreMultiplier(precededBy: $0) },
            [1, 2, 2, 2]
        )
        XCTAssertEqual(
            [0, 1, 2, 3].map { cappedDouble.minimumGameTricks(after: $0) },
            [6, 6, 6, 6]
        )

        XCTAssertEqual(
            [0, 1, 2].map { RaspasyPolicy.singleShot.scoreMultiplier(precededBy: $0) },
            [1, 1, 1]
        )
        XCTAssertEqual(
            [0, 1, 2].map { RaspasyPolicy.singleShot.minimumGameTricks(after: $0) },
            [6, 6, 6]
        )
    }

    func testRaspasyProgressionsSaturateForAnUnboundedSeriesCounter() {
        let stage = Int.max
        XCTAssertEqual(
            RaspasyPolicy.sochi.scoreMultiplier(precededBy: stage),
            3
        )
        XCTAssertEqual(
            RaspasyPolicy.sochi.minimumGameTricks(after: stage),
            8
        )

        let geometric = RaspasyPolicy.progressive(penalties: .geometric, exit: .strict)
        XCTAssertEqual(geometric.scoreMultiplier(precededBy: stage), 4)
        XCTAssertEqual(geometric.minimumGameTricks(after: stage), 8)
    }

    func testStrictRaspasyExitFiltersSixThenSevenLevelGamesButKeepsMisere() throws {
        XCTAssertEqual(try legalGameLevels(after: 0), Set([6, 7, 8, 9, 10]))
        XCTAssertEqual(try legalGameLevels(after: 1), Set([7, 8, 9, 10]))
        XCTAssertEqual(try legalGameLevels(after: 2), Set([8, 9, 10]))
        XCTAssertEqual(try legalGameLevels(after: 8), Set([8, 9, 10]))
    }

    func testEngineCarriesRaspasySeriesAcrossDealsAndResetsAfterAContract() throws {
        var engine = try makeEngine(match: MatchSettings(raspasy: .sochi))

        let first = try finishAllPass(&engine)
        XCTAssertEqual(engine.consecutiveAllPassDeals, 1)
        assertSochiAllPass(first, price: 1)

        let second = try finishAllPass(&engine)
        XCTAssertEqual(engine.consecutiveAllPassDeals, 2)
        assertSochiAllPass(second, price: 2)

        engine = try PreferansEngine(snapshot: engine.snapshot)
        XCTAssertEqual(engine.consecutiveAllPassDeals, 2, "The progression must survive host recovery.")

        try engine.startDeal(deck: Self.northSpadesSixDeck)
        guard case let .bidding(opening) = engine.state else {
            return XCTFail("Expected bidding after starting the exit deal.")
        }
        let exitBid = ContractBid.game(GameContract(8, .suit(.clubs)))
        XCTAssertTrue(engine.legalBidCalls(for: opening.currentPlayer).contains(.bid(exitBid)))
        _ = try engine.apply(.bid(player: opening.currentPlayer, call: .bid(exitBid)))
        while case let .bidding(bidding) = engine.state {
            _ = try engine.apply(.bid(player: bidding.currentPlayer, call: .pass))
        }
        guard case let .awaitingDiscard(exchange) = engine.state else {
            return XCTFail("Expected the eight-level declarer to receive the talon.")
        }
        _ = try engine.apply(.discard(player: exchange.declarer, cards: exchange.talon))
        _ = try engine.apply(.concedeWithoutThree(player: exchange.declarer))

        XCTAssertEqual(engine.consecutiveAllPassDeals, 0)
        guard case let .dealFinished(result) = engine.state,
              case .withoutThree = result.kind else {
            return XCTFail("Expected a non-raspasy result to close the series.")
        }
    }

    private func finishAllPass(_ engine: inout PreferansEngine) throws -> DealResult {
        try engine.startDeal(deck: Self.northSpadesSixDeck)
        while case let .bidding(bidding) = engine.state {
            _ = try engine.apply(.bid(player: bidding.currentPlayer, call: .pass))
        }
        guard case let .playing(playing) = engine.state,
              case .allPass = playing.kind else {
            throw EngineTestError("Expected all-pass play, got \(engine.state.description).")
        }
        try EngineTestDriver.playOut(engine: &engine, policy: .lowestLegal)
        guard case let .dealFinished(result) = engine.state else {
            throw EngineTestError("Expected scored all-pass deal, got \(engine.state.description).")
        }
        return result
    }

    private func assertSochiAllPass(
        _ result: DealResult,
        price: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for player in result.activePlayers {
            let tricks = result.trickCounts[player] ?? 0
            XCTAssertEqual(
                result.scoreDelta.mountain[player],
                tricks * price,
                file: file,
                line: line
            )
            XCTAssertEqual(
                result.scoreDelta.pool[player],
                tricks == 0 ? price : 0,
                file: file,
                line: line
            )
        }
    }

    private func legalGameLevels(after precedingRaspasy: Int) throws -> Set<Int> {
        var engine = try makeEngine(match: MatchSettings(raspasy: .sochi))
        try startDeal(&engine)
        var snapshot = engine.snapshot
        snapshot.dealsPlayed = precedingRaspasy
        snapshot.consecutiveAllPassDeals = precedingRaspasy
        engine = try PreferansEngine(snapshot: snapshot)

        guard case let .bidding(bidding) = engine.state else {
            XCTFail("Expected bidding state")
            return []
        }
        let calls = engine.legalBidCalls(for: bidding.currentPlayer)
        XCTAssertTrue(calls.contains(.bid(.misere)), "Misère remains legal at every stage.")
        return Set(calls.compactMap { call -> Int? in
            guard case let .bid(.game(contract)) = call else { return nil }
            return contract.tricks
        })
    }

    // MARK: - Dedicated totus contract

    func testTotusBidIsIllegalWhenPolicyIsAsTenTrickGame() throws {
        var engine = try makeEngine(
            match: MatchSettings(poolTarget: .max, totus: .asTenTrickGame(requireWhist: false))
        )
        try engine.startDeal(deck: Self.northSpadesSixDeck)

        let calls = engine.legalBidCalls(for: "north")
        XCTAssertFalse(calls.contains(.bid(.totus)),
                       "Totus must not appear unless the match opts into the dedicated contract.")
        XCTAssertTrue(calls.contains(.bid(.game(GameContract(10, .suit(.spades))))),
                      "10-trick game contracts must remain legal under asTenTrickGame.")
    }

    func testTotusBidIsLegalAndTenTrickGamesSuppressedUnderDedicatedPolicy() throws {
        var engine = try makeEngine(
            match: MatchSettings(
                poolTarget: .max,
                totus: .dedicatedContract(requireWhist: true, bonusPool: 5)
            )
        )
        try engine.startDeal(deck: Self.northSpadesSixDeck)

        let calls = engine.legalBidCalls(for: "north")
        XCTAssertTrue(calls.contains(.bid(.totus)),
                      "Totus must be a legal bid under dedicatedContract.")
        for strain in Strain.allStandard {
            let tenTrickCall = BidCall.bid(.game(GameContract(10, strain)))
            XCTAssertFalse(calls.contains(tenTrickCall),
                           "10-\(strain) game bid must be suppressed when totus is dedicated.")
        }
    }

    func testTenTrickGameStartsPlayWithoutWhist() throws {
        var engine = try makeEngine(
            match: MatchSettings(poolTarget: .max, totus: .asTenTrickGame(requireWhist: false))
        )
        let deck = HandRecipe
            .totusMakes(declarer: "north", strain: .suit(.spades))
            .deck(for: ["north", "east", "south"])
        try engine.startDeal(deck: deck)

        let contract = GameContract(10, .suit(.spades))
        _ = try engine.apply(.bid(player: "north", call: .bid(.game(contract))))
        _ = try engine.apply(.bid(player: "east", call: .pass))
        _ = try engine.apply(.bid(player: "south", call: .pass))

        guard case let .awaitingDiscard(exchange) = engine.state else {
            return XCTFail("10-trick auction win should open the discard window.")
        }
        _ = try engine.apply(.discard(player: "north", cards: exchange.talon))

        let events = try engine.apply(.declareContract(player: "north", contract: contract))

        XCTAssertTrue(events.contains { if case .playStarted = $0 { return true } else { return false } },
                      "10-trick contracts must skip whist/pass and start play immediately.")
        guard case let .playing(playing) = engine.state,
              case let .game(context) = playing.kind else {
            return XCTFail("Expected 10-trick contract to enter card play.")
        }
        XCTAssertEqual(context.contract, contract)
        XCTAssertEqual(context.whisters, [])
        XCTAssertTrue(engine.legalWhistCalls(for: "east").isEmpty)

        try EngineTestDriver.playOut(engine: &engine, policy: .declarerHighestDefendersLowest(declarer: "north"))

        guard case let .dealFinished(result) = engine.state,
              case let .game(declarer, finishedContract, whisters) = result.kind else {
            return XCTFail("Expected played 10-trick game result.")
        }
        XCTAssertEqual(declarer, "north")
        XCTAssertEqual(finishedContract, contract)
        XCTAssertEqual(whisters, [])
        XCTAssertEqual(engine.score.pool["north"], 10)
    }

    func testDedicatedTotusFlowCreditsBonusPoolAfterPlayedWin() throws {
        var engine = try makeEngine(
            match: MatchSettings(
                poolTarget: .max,
                totus: .dedicatedContract(requireWhist: true, bonusPool: 5)
            )
        )
        let deck = HandRecipe
            .totusMakes(declarer: "north", strain: .suit(.spades))
            .deck(for: ["north", "east", "south"])
        try engine.startDeal(deck: deck)

        _ = try engine.apply(.bid(player: "north", call: .bid(.totus)))
        _ = try engine.apply(.bid(player: "east", call: .pass))
        _ = try engine.apply(.bid(player: "south", call: .pass))

        guard case let .awaitingDiscard(exchange) = engine.state else {
            return XCTFail("Totus auction win should open the discard window.")
        }
        XCTAssertEqual(exchange.declarer, "north")
        XCTAssertEqual(exchange.finalBid, .totus)

        _ = try engine.apply(.discard(player: "north", cards: exchange.talon))

        guard case .awaitingContract = engine.state else {
            return XCTFail("Totus discard should advance to contract declaration.")
        }
        let options = engine.legalContractDeclarations(for: "north")
        XCTAssertEqual(options.count, Strain.allStandard.count,
                       "Totus declaration must offer exactly one contract per strain.")
        XCTAssertTrue(options.allSatisfy { $0.tricks == 10 },
                      "Totus declaration is constrained to 10-trick contracts.")

        _ = try engine.apply(.declareContract(player: "north", contract: GameContract(10, .suit(.spades))))

        // The dedicated policy enables the normal whist decision. This
        // fixture deliberately has both defenders accept the risk.
        var whisters: [PlayerID] = []
        while case let .awaitingWhist(whist) = engine.state {
            XCTAssertEqual(engine.legalWhistCalls(for: whist.currentPlayer), [.pass, .whist])
            whisters.append(whist.currentPlayer)
            _ = try engine.apply(.whist(player: whist.currentPlayer, call: .whist))
        }
        guard case let .playing(playing) = engine.state,
              case let .game(context) = playing.kind else {
            return XCTFail("Totus declaration should enter card play after both defenders choose whist.")
        }
        XCTAssertEqual(context.whisters, whisters)
        XCTAssertEqual(whisters.count, 2)

        try EngineTestDriver.playOut(engine: &engine, policy: .declarerHighestDefendersLowest(declarer: "north"))

        guard case let .dealFinished(result) = engine.state,
              case .game = result.kind else {
            return XCTFail("Totus should finish only after card play.")
        }
        // Contract value (10-5)*2 = 10; bonus = 5; total = 15.
        XCTAssertEqual(engine.score.pool["north"], 15,
                       "Declarer must receive contract value plus totus bonus on a played win.")
        // Responsible whist at requirement 1: the defense took no trick, so
        // the second whister owes one trick's value on the mountain.
        XCTAssertEqual(engine.score.mountain[whisters[1]], 10,
                       "A defender who whists carries the 1-trick responsibility quota.")
    }

    func testTotusOrderingPlacesItDirectlyAboveMisere() {
        let nineSpades = ContractBid.game(GameContract(9, .suit(.spades)))
        XCTAssertLessThan(ContractBid.misere, ContractBid.totus,
                          "Totus must outrank misère in the bid ladder.")
        XCTAssertEqual(ContractBid.totus.order - ContractBid.misere.order, 1,
                       "Totus should sit immediately above misère in the bid order.")
        XCTAssertLessThan(ContractBid.totus, nineSpades,
                          "Nine spades must still overcall the dedicated Totus slot.")
        XCTAssertEqual(nineSpades.order - ContractBid.totus.order, 1)

        let orders = ContractBid.allStandard.map(\.order)
        XCTAssertEqual(Set(orders).count, orders.count,
                       "Distinct bids must never compare at the same rank.")
    }

    func testNineSpadesCanOvercallTotusButTotusCannotOvercallNineSpades() throws {
        var engine = try makeEngine(
            match: MatchSettings(
                poolTarget: .max,
                totus: .dedicatedContract(requireWhist: true, bonusPool: 5)
            )
        )
        try engine.startDeal(deck: Self.northSpadesSixDeck)
        let nineSpades = BidCall.bid(.game(GameContract(9, .suit(.spades))))

        _ = try engine.apply(.bid(player: "north", call: .bid(.totus)))
        XCTAssertTrue(engine.legalBidCalls(for: "east").contains(nineSpades))

        _ = try engine.apply(.bid(player: "east", call: nineSpades))
        XCTAssertFalse(engine.legalBidCalls(for: "south").contains(.bid(.totus)))
    }
}
