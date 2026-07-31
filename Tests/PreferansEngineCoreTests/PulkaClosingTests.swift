import XCTest
@testable import PreferansEngine
@testable import PreferansEngineTestSupport

final class PulkaClosingTests: XCTestCase {
    private let players: [PlayerID] = ["north", "east", "south"]

    func testSurplusPoolAidsHighestOpenPlayerAndWritesWhists() {
        var score = makeScore(pool: ["north": 10, "east": 7, "south": 3])
        var delta = ScoreDelta(players: players)
        delta.addPool(4, to: "north")

        let applied = score.apply(delta, closingAtPoolTarget: 33)

        XCTAssertEqual(score.pool, ["north": 11, "east": 10, "south": 3])
        XCTAssertEqual(score.whistsWritten(by: "north", on: "east"), 30)
        XCTAssertEqual(score.whistsWritten(by: "north", on: "south"), 0)
        XCTAssertEqual(applied.pool, ["north": 1, "east": 3, "south": 0])
        XCTAssertEqual(applied.whists["north"]?["east"], 30)
    }

    func testLeningradTableTotalLeavesIndividualPoolsOpenWithoutAmericanAid() {
        var score = makeScore(pool: ["north": 10, "east": 7, "south": 3])
        var delta = ScoreDelta(players: players)
        delta.addPool(4, to: "north")

        let applied = score.apply(
            delta,
            closingAtPoolTarget: 33,
            poolClosure: .tableTotal,
            poolPointWhistValue: PreferansRules.leningrad.poolPointWhistValue
        )

        XCTAssertEqual(score.pool, ["north": 14, "east": 7, "south": 3])
        XCTAssertEqual(score.whistsWritten(by: "north", on: "east"), 0)
        XCTAssertEqual(score.whistsWritten(by: "north", on: "south"), 0)
        XCTAssertEqual(applied, delta)
    }

    func testLeningradFinalBalanceUsesDifferentPoolAndMountainRates() {
        let score = makeScore(
            pool: ["north": 1, "east": 0, "south": 0],
            mountain: ["north": 0, "east": 1, "south": 0]
        )

        let balances = score.normalizedBalances(
            poolPointValue: Double(PreferansRules.leningrad.poolPointWhistValue),
            mountainPointValue: Double(PreferansRules.leningrad.mountainPointWhistValue)
        )

        XCTAssertEqual(balances["north"] ?? 0, 50.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(balances["east"] ?? 0, -40.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(balances["south"] ?? 0, -10.0 / 3.0, accuracy: 0.000_001)
        XCTAssertEqual(balances.values.reduce(0, +), 0, accuracy: 0.000_001)
    }

    func testSurplusPoolCascadesAcrossPlayersThenReducesMountainWhenEveryoneIsClosed() {
        var score = makeScore(pool: ["north": 10, "east": 10, "south": 8])
        var delta = ScoreDelta(players: players)
        delta.addPool(6, to: "north")

        let applied = score.apply(delta, closingAtPoolTarget: 33)

        XCTAssertEqual(score.pool, ["north": 11, "east": 11, "south": 11])
        XCTAssertEqual(score.mountain["north"], -1)
        XCTAssertEqual(score.whistsWritten(by: "north", on: "east"), 10)
        XCTAssertEqual(score.whistsWritten(by: "north", on: "south"), 30)
        XCTAssertEqual(applied.pool, ["north": 1, "east": 1, "south": 3])
        XCTAssertEqual(applied.mountain["north"], -1)
        XCTAssertEqual(applied.whists["north"]?["east"], 10)
        XCTAssertEqual(applied.whists["north"]?["south"], 30)
    }

    func testAidRecipientTieBreaksTowardEarlierSeatOrder() {
        var score = makeScore(pool: ["north": 10, "east": 5, "south": 5])
        var delta = ScoreDelta(players: players)
        delta.addPool(3, to: "north")

        let applied = score.apply(delta, closingAtPoolTarget: 33)

        // Per-player target 33 / 3 = 11. North has room for 1 (11 - 10);
        // the surplus 2 aids the highest open opponent — east and south tie
        // at 5, so the earlier seat in player order (east) receives all of
        // it, with 2 * 10 = 20 whists written back to north.
        XCTAssertEqual(score.pool, ["north": 11, "east": 7, "south": 5])
        XCTAssertEqual(score.whistsWritten(by: "north", on: "east"), 20)
        XCTAssertEqual(score.whistsWritten(by: "north", on: "south"), 0)
        XCTAssertEqual(applied.pool, ["north": 1, "east": 2, "south": 0])
        XCTAssertEqual(applied.whists["north"]?["east"], 20)
    }

    func testTableTotalAppliesPoolWithoutRequiringPlayerDivisibility() {
        var score = makeScore(pool: ["north": 9, "east": 0, "south": 0])
        var delta = ScoreDelta(players: players)
        delta.addPool(5, to: "north")

        // A shared Leningrad table total need not divide by the player count.
        // Entries remain verbatim: no cap, aid, whists, or mountain relief.
        let applied = score.apply(
            delta,
            closingAtPoolTarget: 10,
            poolClosure: .tableTotal
        )

        XCTAssertEqual(score.pool, ["north": 14, "east": 0, "south": 0])
        XCTAssertEqual(score.mountain, ["north": 0, "east": 0, "south": 0])
        XCTAssertEqual(score.whistsWritten(by: "north", on: "east"), 0)
        XCTAssertEqual(score.whistsWritten(by: "north", on: "south"), 0)
        XCTAssertEqual(applied, delta)
    }

    func testLeningradMatchClosesOnSharedTotalAndAllowsTheWinnerToOvershoot() throws {
        var engine = try makeEngine(
            pool: ["north": 20, "east": 0, "south": 0],
            rules: .leningrad,
            match: MatchSettings(poolTarget: 21, poolClosure: .tableTotal),
            firstDealer: "south"
        )
        try engine.startDeal(deck: Self.northSpadesSixDeck)

        let contract = GameContract(6, .suit(.clubs))
        _ = try engine.apply(.bid(player: "north", call: .bid(.game(contract))))
        _ = try engine.apply(.bid(player: "east", call: .pass))
        _ = try engine.apply(.bid(player: "south", call: .pass))
        guard case let .awaitingDiscard(exchange) = engine.state else {
            return XCTFail("Expected north to discard.")
        }
        _ = try engine.apply(.discard(player: "north", cards: exchange.talon))
        _ = try engine.apply(.declareContract(player: "north", contract: contract))
        _ = try engine.apply(.whist(player: "east", call: .pass))
        let events = try engine.apply(.whist(player: "south", call: .pass))

        XCTAssertTrue(events.contains { if case .matchEnded = $0 { return true } else { return false } })
        guard case .gameOver = engine.state else {
            return XCTFail("The shared pool total should close at or beyond 21.")
        }
        XCTAssertEqual(engine.score.pool, ["north": 22, "east": 0, "south": 0])
        XCTAssertEqual(engine.score.whistsWritten(by: "north", on: "east"), 0)
        XCTAssertEqual(engine.score.whistsWritten(by: "north", on: "south"), 0)
    }

    func testFourPlayerMatchClosesAndAidsSittingOutDealer() throws {
        let players4: [PlayerID] = ["north", "east", "south", "west"]
        let score = ScoreSheet(
            uncheckedPlayers: players4,
            pool: ["north": 1, "east": 2, "south": 2, "west": 2],
            mountain: players4.dictionary(filledWith: 0),
            whists: players4.dictionary(filledWith: [:])
        )
        let snapshot = PreferansSnapshot(
            players: players4,
            rules: .sochi,
            match: MatchSettings(poolTarget: 8), // per-player target 8 / 4 = 2
            state: .waitingForDeal,
            score: score,
            nextDealer: "north"
        )
        var engine = try PreferansEngine(snapshot: snapshot)
        try engine.startDeal(deck: Deck.standard32)

        // North deals and sits out; rotation is [east, south, west].
        let contract = GameContract(6, .suit(.clubs))
        try EngineTestDriver.driveAuctionWinning(engine: &engine, declarer: "east", bid: .game(contract))
        try EngineTestDriver.discardTalon(engine: &engine, declarer: "east")
        _ = try engine.apply(.declareContract(player: "east", contract: contract))
        _ = try engine.apply(.whist(player: "south", call: .pass))
        let events = try engine.apply(.whist(player: "west", call: .pass))

        // Passed out: +2 pool to east. East is already closed at 2, so the
        // whole surplus aids the only open player — the sitting-out dealer
        // north — who has room for 1 (whists 1 * 10 = 10 back to east); the
        // final leftover 1 reduces east's mountain. Total pool 8 >= 8 closes
        // the match.
        XCTAssertTrue(events.contains { if case .matchEnded = $0 { return true } else { return false } })
        guard case let .gameOver(summary) = engine.state else {
            return XCTFail("Expected the 4-player pulka to close; got \(engine.state.description).")
        }
        XCTAssertEqual(engine.score.pool, ["north": 2, "east": 2, "south": 2, "west": 2])
        XCTAssertEqual(engine.score.mountain, ["north": 0, "east": -1, "south": 0, "west": 0])
        XCTAssertEqual(engine.score.whistsWritten(by: "east", on: "north"), 10)
        XCTAssertEqual(summary.standings.count, 4)
        XCTAssertEqual(Set(summary.standings.map(\.player)), Set(players4))
        XCTAssertEqual(summary.finalScore, engine.score)
    }

    func testEngineDealAppliesPulkaClosingToDealResultAndMatchSummary() throws {
        var engine = try makeEngine(
            pool: ["north": 10, "east": 10, "south": 10],
            match: MatchSettings(poolTarget: 33),
            firstDealer: "south"
        )
        try engine.startDeal(deck: Self.northSpadesSixDeck)

        let contract = GameContract(7, .suit(.clubs))
        _ = try engine.apply(.bid(player: "north", call: .bid(.game(contract))))
        _ = try engine.apply(.bid(player: "east", call: .pass))
        _ = try engine.apply(.bid(player: "south", call: .pass))

        guard case let .awaitingDiscard(exchange) = engine.state else {
            return XCTFail("Expected north to discard.")
        }
        _ = try engine.apply(.discard(player: "north", cards: exchange.talon))
        _ = try engine.apply(.declareContract(player: "north", contract: contract))
        _ = try engine.apply(.whist(player: "east", call: .pass))
        let events = try engine.apply(.whist(player: "south", call: .pass))

        XCTAssertTrue(events.contains { if case .matchEnded = $0 { return true } else { return false } })
        guard case let .gameOver(summary) = engine.state else {
            return XCTFail("Expected the short pulka to close; got \(engine.state.description).")
        }
        let scoredResult = try XCTUnwrap(events.compactMap { event -> DealResult? in
            if case let .dealScored(result) = event { return result }
            return nil
        }.first)

        XCTAssertEqual(engine.score.pool, ["north": 11, "east": 11, "south": 11])
        XCTAssertEqual(engine.score.mountain["north"], -1)
        XCTAssertEqual(engine.score.whistsWritten(by: "north", on: "east"), 10)
        XCTAssertEqual(engine.score.whistsWritten(by: "north", on: "south"), 10)
        XCTAssertEqual(scoredResult.scoreDelta.pool, ["north": 1, "east": 1, "south": 1])
        XCTAssertEqual(scoredResult.scoreDelta.mountain["north"], -1)
        XCTAssertEqual(scoredResult.scoreDelta.whists["north"]?["east"], 10)
        XCTAssertEqual(scoredResult.scoreDelta.whists["north"]?["south"], 10)
        XCTAssertEqual(summary.lastDeal.scoreDelta, scoredResult.scoreDelta)
        XCTAssertEqual(summary.finalScore, engine.score)
    }

    private func makeScore(
        pool: [PlayerID: Int],
        mountain: [PlayerID: Int]? = nil
    ) -> ScoreSheet {
        ScoreSheet(
            uncheckedPlayers: players,
            pool: pool,
            mountain: mountain ?? emptyInts(),
            whists: emptyWhists()
        )
    }

    private func makeEngine(
        pool: [PlayerID: Int],
        rules: PreferansRules = .sochi,
        match: MatchSettings,
        firstDealer: PlayerID
    ) throws -> PreferansEngine {
        let score = ScoreSheet(
            uncheckedPlayers: players,
            pool: pool,
            mountain: emptyInts(),
            whists: emptyWhists()
        )
        let snapshot = PreferansSnapshot(
            players: players,
            rules: rules,
            match: match,
            state: .waitingForDeal,
            score: score,
            nextDealer: firstDealer
        )
        return try PreferansEngine(snapshot: snapshot)
    }

    private func emptyInts() -> [PlayerID: Int] {
        Dictionary(uniqueKeysWithValues: players.map { ($0, 0) })
    }

    private func emptyWhists() -> [PlayerID: [PlayerID: Int]] {
        Dictionary(uniqueKeysWithValues: players.map { ($0, [:]) })
    }

    private static let northSpadesSixDeck: [Card] = {
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
}
