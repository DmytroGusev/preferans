import XCTest
@testable import PreferansEngine

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
            rules: .sochi,
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
