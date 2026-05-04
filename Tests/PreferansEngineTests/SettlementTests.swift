import XCTest
@testable import PreferansApp
@testable import PreferansEngine

final class SettlementTests: XCTestCase {
    private let players: [PlayerID] = ["north", "east", "south"]

    func testUnanimousSettlementScoresDealWithoutFabricatingTricks() throws {
        var engine = try makeGamePlayingEngine()
        let settlement = TrickSettlement(
            target: "east",
            targetTricks: 6,
            finalTrickCounts: ["east": 6, "south": 2, "north": 2]
        )

        let proposed = try engine.apply(.proposeSettlement(player: "east", settlement: settlement))
        XCTAssertEqual(proposed, [
            .settlementProposed(TrickSettlementProposal(
                proposer: "east",
                settlement: settlement,
                acceptedBy: ["east"]
            ))
        ])
        XCTAssertEqual(engine.state.currentActor, "south")
        XCTAssertThrowsError(try engine.apply(.playCard(player: "east", card: Deck.standard32[0])))

        _ = try engine.apply(.acceptSettlement(player: "south"))
        let finalEvents = try engine.apply(.acceptSettlement(player: "north"))

        XCTAssertTrue(finalEvents.contains(.playSettled(settlement)))
        guard case let .dealFinished(result) = engine.state else {
            return XCTFail("Expected the settlement to score the deal.")
        }
        XCTAssertEqual(result.settlement, settlement)
        XCTAssertEqual(result.trickCounts, settlement.finalTrickCounts)
        XCTAssertEqual(result.completedTricks, [])
        XCTAssertEqual(engine.score.pool["east"], 2)
        XCTAssertEqual(engine.score.whistsWritten(by: "south", on: "east"), 4)
        XCTAssertEqual(engine.score.whistsWritten(by: "north", on: "east"), 4)
    }

    func testRejectingSettlementResumesCardPlay() throws {
        var engine = try makeGamePlayingEngine()
        let settlement = TrickSettlement(
            target: "east",
            targetTricks: 6,
            finalTrickCounts: ["east": 6, "south": 2, "north": 2]
        )

        _ = try engine.apply(.proposeSettlement(player: "east", settlement: settlement))
        let events = try engine.apply(.rejectSettlement(player: "south"))

        XCTAssertEqual(events, [.settlementRejected(player: "south")])
        guard case let .playing(playing) = engine.state else {
            return XCTFail("Expected card play to resume.")
        }
        XCTAssertNil(playing.pendingSettlement)
        XCTAssertEqual(engine.legalCards(for: playing.currentPlayer).count, 10)
    }

    func testSettlementRejectsImpossibleFinalCounts() throws {
        var engine = try makeGamePlayingEngine()
        let invalid = TrickSettlement(
            target: "east",
            targetTricks: 6,
            finalTrickCounts: ["east": 6, "south": 2, "north": 1]
        )

        XCTAssertThrowsError(try engine.apply(.proposeSettlement(player: "east", settlement: invalid))) { error in
            XCTAssertEqual(
                error as? PreferansError,
                .illegalSettlement("Settlement final trick counts must total 10.")
            )
        }
    }

    func testSettlementActionRoundTripsThroughJSON() throws {
        let settlement = TrickSettlement(
            target: "east",
            targetTricks: 6,
            finalTrickCounts: ["east": 6, "south": 2, "north": 2]
        )
        let action = PreferansAction.proposeSettlement(player: "north", settlement: settlement)

        let encoded = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(PreferansAction.self, from: encoded)

        XCTAssertEqual(decoded, action)
    }

    func testProjectionExposesSettlementActionsToViewers() throws {
        var engine = try makeGamePlayingEngine()
        let settlement = try XCTUnwrap(engine.legalSettlements(for: "east").first {
            $0.target == "east" && $0.targetTricks == 6
        })
        _ = try engine.apply(.proposeSettlement(player: "east", settlement: settlement))

        let southProjection = PlayerProjectionBuilder.projection(
            for: "south",
            tableID: UUID(),
            sequence: 1,
            engine: engine,
            policy: .online
        )
        XCTAssertEqual(southProjection.legal.pendingSettlement?.settlement, settlement)
        XCTAssertTrue(southProjection.legal.canAcceptSettlement)
        XCTAssertTrue(southProjection.legal.canRejectSettlement)

        let eastProjection = PlayerProjectionBuilder.projection(
            for: "east",
            tableID: UUID(),
            sequence: 1,
            engine: engine,
            policy: .online
        )
        XCTAssertFalse(eastProjection.legal.canAcceptSettlement)
        XCTAssertTrue(eastProjection.legal.canRejectSettlement)
    }

    func testBotProposesAndAcceptsDeterministicLastTrickSettlement() async throws {
        let strategy = HeuristicStrategy(planner: CardPlayPlanner(samples: 1, rolloutsPerSample: 1))
        var engine = try makeLastTrickEngine()

        let drive = try await BotTestDriver.drive(engine: &engine, strategy: strategy, stepLimit: 4)

        XCTAssertFalse(drive.stalled, "Bots should settle the deterministic last trick.")
        XCTAssertLessThanOrEqual(drive.steps, 3)
        guard case let .dealFinished(result) = engine.state else {
            return XCTFail("Expected settlement to finish the deal.")
        }
        XCTAssertNotNil(result.settlement)
        XCTAssertEqual(result.trickCounts.values.reduce(0, +), 10)
    }

    private func makeGamePlayingEngine() throws -> PreferansEngine {
        var engine = try PreferansEngine(players: players, firstDealer: "north")
        _ = try engine.startDeal(deck: Deck.standard32)
        _ = try engine.apply(.bid(player: "east", call: .bid(.game(GameContract(6, .suit(.clubs))))))
        _ = try engine.apply(.bid(player: "south", call: .pass))
        _ = try engine.apply(.bid(player: "north", call: .pass))
        try EngineTestDriver.discardTalon(engine: &engine, declarer: "east")
        try EngineTestDriver.declareContract(engine: &engine, declarer: "east", contract: GameContract(6, .suit(.clubs)))
        try EngineTestDriver.forceWhist(engine: &engine)
        return engine
    }

    private func makeLastTrickEngine() throws -> PreferansEngine {
        var engine = try makeGamePlayingEngine()
        while case let .playing(playing) = engine.state, playing.completedTricks.count < 9 {
            let actor = playing.currentPlayer
            let card = try XCTUnwrap(engine.legalCards(for: actor).min())
            _ = try engine.apply(.playCard(player: actor, card: card))
        }
        guard case .playing = engine.state else {
            throw EngineTestError("Expected playing state before last trick.")
        }
        return engine
    }
}
