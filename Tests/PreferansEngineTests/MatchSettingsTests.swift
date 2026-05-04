import XCTest
@testable import PreferansEngine

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

    func testGameOverFiresWhenPoolSumCrossesTargetExactly() throws {
        var engine = try makeEngine(match: MatchSettings(poolTarget: 2))
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
        var engine = try makeEngine(match: MatchSettings(poolTarget: 10))
        _ = try runPassedOutSixClubs(&engine)

        guard case .dealFinished = engine.state else {
            return XCTFail("Pool sum 2 < target 10 should keep the engine open.")
        }
        XCTAssertEqual(engine.dealsPlayed, 1)
    }

    func testStartDealFromGameOverThrows() throws {
        var engine = try makeEngine(match: MatchSettings(poolTarget: 2))
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
        var engine = try makeEngine(match: MatchSettings(poolTarget: 2))
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

        let declareEvents = try engine.apply(.declareContract(player: "north", contract: GameContract(10, .suit(.spades))))

        XCTAssertTrue(declareEvents.contains { if case .playStarted = $0 { return true } else { return false } },
                      "Dedicated totus must skip whist/pass and start play immediately.")
        guard case let .playing(playing) = engine.state,
              case let .game(context) = playing.kind else {
            return XCTFail("Totus declaration should enter card play.")
        }
        XCTAssertEqual(context.whisters, [])
        XCTAssertTrue(engine.legalWhistCalls(for: "east").isEmpty)

        try EngineTestDriver.playOut(engine: &engine, policy: .declarerHighestDefendersLowest(declarer: "north"))

        guard case let .dealFinished(result) = engine.state,
              case .game = result.kind else {
            return XCTFail("Totus should finish only after card play.")
        }
        // Contract value (10-5)*2 = 10; bonus = 5; total = 15.
        XCTAssertEqual(engine.score.pool["north"], 15,
                       "Declarer must receive contract value plus totus bonus on a played win.")
    }

    func testTotusOrderingPlacesItDirectlyAboveMisere() {
        // Totus is the only bid that sits between misère and the (suppressed)
        // 10-trick game contracts — comparing it against the standard ladder's
        // 10♠/10NT is moot because dedicatedContract mode removes those bids
        // from the legal-call list.
        XCTAssertLessThan(ContractBid.misere, ContractBid.totus,
                          "Totus must outrank misère in the bid ladder.")
        XCTAssertEqual(ContractBid.totus.order - ContractBid.misere.order, 1,
                       "Totus should sit immediately above misère in the bid order.")
    }
}
