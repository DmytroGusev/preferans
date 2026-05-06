import Foundation
import Testing
@testable import PreferansApp
@testable import PreferansEngine

@Suite("Trick settlement")
struct SettlementTests {
    private let players: [PlayerID] = ["north", "east", "south"]

    @Test("Unanimous settlement scores the deal without fabricating tricks")
    func unanimousSettlementScoresDeal() throws {
        var engine = try makeGamePlayingEngine()
        let settlement = TrickSettlement(
            target: "east",
            targetTricks: 6,
            finalTrickCounts: ["east": 6, "south": 2, "north": 2]
        )

        let proposed = try engine.apply(.proposeSettlement(player: "east", settlement: settlement))
        #expect(proposed == [
            .settlementProposed(TrickSettlementProposal(
                proposer: "east",
                settlement: settlement,
                acceptedBy: ["east"]
            ))
        ])
        #expect(engine.state.currentActor == "south")
        #expect(throws: (any Error).self) {
            try engine.apply(.playCard(player: "east", card: Deck.standard32[0]))
        }

        _ = try engine.apply(.acceptSettlement(player: "south"))
        let finalEvents = try engine.apply(.acceptSettlement(player: "north"))

        #expect(finalEvents.contains(.playSettled(settlement)))
        guard case let .dealFinished(result) = engine.state else {
            Issue.record("Expected the settlement to score the deal.")
            return
        }
        #expect(result.settlement == settlement)
        #expect(result.trickCounts == settlement.finalTrickCounts)
        #expect(result.completedTricks == [])
        #expect(engine.score.pool["east"] == 2)
        #expect(engine.score.whistsWritten(by: "south", on: "east") == 4)
        #expect(engine.score.whistsWritten(by: "north", on: "east") == 4)
    }

    @Test("Rejecting settlement resumes card play")
    func rejectingSettlementResumesCardPlay() throws {
        var engine = try makeGamePlayingEngine()
        let settlement = TrickSettlement(
            target: "east",
            targetTricks: 6,
            finalTrickCounts: ["east": 6, "south": 2, "north": 2]
        )

        _ = try engine.apply(.proposeSettlement(player: "east", settlement: settlement))
        let events = try engine.apply(.rejectSettlement(player: "south"))

        #expect(events == [.settlementRejected(player: "south")])
        guard case let .playing(playing) = engine.state else {
            Issue.record("Expected card play to resume.")
            return
        }
        #expect(playing.pendingSettlement == nil)
        #expect(engine.legalCards(for: playing.currentPlayer).count == 10)
    }

    @Test("Settlement rejects impossible final counts")
    func settlementRejectsImpossibleFinalCounts() throws {
        var engine = try makeGamePlayingEngine()
        let invalid = TrickSettlement(
            target: "east",
            targetTricks: 6,
            finalTrickCounts: ["east": 6, "south": 2, "north": 1]
        )

        #expect {
            try engine.apply(.proposeSettlement(player: "east", settlement: invalid))
        } throws: { error in
            (error as? PreferansError) == .illegalSettlement("Settlement final trick counts must total 10.")
        }
    }

    @Test("Settlement action round-trips through JSON")
    func settlementActionRoundTripsThroughJSON() throws {
        let settlement = TrickSettlement(
            target: "east",
            targetTricks: 6,
            finalTrickCounts: ["east": 6, "south": 2, "north": 2]
        )
        let action = PreferansAction.proposeSettlement(player: "north", settlement: settlement)

        let encoded = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(PreferansAction.self, from: encoded)

        #expect(decoded == action)
    }

    @Test("Projection exposes settlement actions to viewers")
    func projectionExposesSettlementActions() throws {
        var engine = try makeGamePlayingEngine()
        let settlement = try #require(engine.legalSettlements(for: "east").first {
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
        #expect(southProjection.legal.pendingSettlement?.settlement == settlement)
        #expect(southProjection.legal.canAcceptSettlement)
        #expect(southProjection.legal.canRejectSettlement)

        let eastProjection = PlayerProjectionBuilder.projection(
            for: "east",
            tableID: UUID(),
            sequence: 1,
            engine: engine,
            policy: .online
        )
        #expect(!eastProjection.legal.canAcceptSettlement)
        #expect(eastProjection.legal.canRejectSettlement)
    }

    @Test("Bot proposes and accepts deterministic last-trick settlement")
    func botSettlesDeterministicLastTrick() async throws {
        let strategy = HeuristicStrategy(planner: CardPlayPlanner(samples: 1, rolloutsPerSample: 1))
        var engine = try makeLastTrickEngine()

        let drive = try await BotTestDriver.drive(engine: &engine, strategy: strategy, stepLimit: 4)

        #expect(!drive.stalled, "Bots should settle the deterministic last trick.")
        #expect(drive.steps <= 3)
        guard case let .dealFinished(result) = engine.state else {
            Issue.record("Expected settlement to finish the deal.")
            return
        }
        #expect(result.settlement != nil)
        #expect(result.trickCounts.values.reduce(0, +) == 10)
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
            let card = try #require(engine.legalCards(for: actor).min())
            _ = try engine.apply(.playCard(player: actor, card: card))
        }
        guard case .playing = engine.state else {
            throw EngineTestError("Expected playing state before last trick.")
        }
        return engine
    }
}
