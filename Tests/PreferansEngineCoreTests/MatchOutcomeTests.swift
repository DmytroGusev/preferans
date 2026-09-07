import XCTest
@testable import PreferansEngine

final class MatchOutcomeTests: XCTestCase {
    func testThreeEqualPoolsShareTheLeadAndProjectionNamesNoSoleWinner() throws {
        let engine = try finishPassedContracts([6, 6, 6])
        guard case let .gameOver(summary) = engine.state else { return XCTFail("Match did not close") }
        XCTAssertEqual(summary.standings.map(\.balance), [0, 0, 0])
        XCTAssertEqual(summary.leadingPlayers, ["north", "east", "south"])
        XCTAssertNil(summary.soleWinner)
        XCTAssertEqual(engine.players.map { summary.rank(of: $0) }, [1, 1, 1])
        let projection = PlayerProjectionBuilder.projection(
            for: "south", tableID: UUID(), sequence: 21, engine: engine
        )
        XCTAssertEqual(projection.status, .matchOver(winner: nil))
    }

    func testAmericanAidProducesASoleWinnerIndependentOfLastDeclarer() throws {
        let engine = try finishPassedContracts([7, 6])
        guard case let .gameOver(summary) = engine.state else { return XCTFail("Match did not close") }
        // North filled east's pool for 20 whists; east then filled south's
        // pool for 20. Equal final pools cancel, leaving [20, 0, -20].
        XCTAssertEqual(summary.standings.map(\.balance), [20, 0, -20])
        XCTAssertEqual(summary.soleWinner, "north")
        XCTAssertEqual(engine.players.map { summary.rank(of: $0) }, [1, 2, 3])
        XCTAssertNil(summary.rank(of: "absent"))
    }

    private func finishPassedContracts(_ levels: [Int]) throws -> PreferansEngine {
        let players: [PlayerID] = ["north", "east", "south"]
        var engine = try PreferansEngine(
            players: players, rules: .sochi,
            match: MatchSettings(poolTarget: 6), firstDealer: "south"
        )
        for (index, level) in levels.enumerated() {
            try engine.startDeal(deck: Deck.standard32)
            let declarer = players[index % 3]
            let contract = GameContract(level, .suit(.spades))
            _ = try engine.apply(.bid(player: declarer, call: .bid(.game(contract))))
            for offset in 1...2 {
                _ = try engine.apply(.bid(player: players[(index + offset) % 3], call: .pass))
            }
            guard case let .awaitingDiscard(exchange) = engine.state else {
                XCTFail("Expected prikup"); return engine
            }
            _ = try engine.apply(.discard(player: declarer, cards: exchange.talon))
            _ = try engine.apply(.declareContract(player: declarer, contract: contract))
            for offset in 1...2 {
                _ = try engine.apply(.whist(player: players[(index + offset) % 3], call: .pass))
            }
        }
        return engine
    }
}
