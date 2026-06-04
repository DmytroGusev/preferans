import Foundation
import Testing
@testable import PreferansApp
@testable import PreferansEngine

@Suite("Trick settlement")
struct SettlementTests {
    private let players: [PlayerID] = ["north", "east", "south"]

    @Test("Unanimous settlement scores the deal without fabricating tricks")
    func unanimousSettlementScoresDeal() throws {
        var engine = try makeMisereEngine()
        let settlement = try #require(engine.legalSettlements(for: "north").first)

        let proposed = try engine.apply(.proposeSettlement(player: "north", settlement: settlement))
        #expect(proposed == [
            .settlementProposed(TrickSettlementProposal(
                proposer: "north",
                settlement: settlement,
                acceptedBy: ["north"]
            ))
        ])
        #expect(engine.state.currentActor == "east")
        #expect(throws: (any Error).self) {
            try engine.apply(.playCard(player: "east", card: Deck.standard32[0]))
        }

        _ = try engine.apply(.acceptSettlement(player: "east"))
        let finalEvents = try engine.apply(.acceptSettlement(player: "south"))

        #expect(finalEvents.contains(.playSettled(settlement)))
        guard case let .dealFinished(result) = engine.state else {
            Issue.record("Expected the settlement to score the deal.")
            return
        }
        #expect(result.settlement == settlement)
        #expect(result.trickCounts == settlement.finalTrickCounts)
        // Settling concedes the unplayed tricks, so no cards were played.
        #expect(result.completedTricks.isEmpty)
    }

    @Test("Rejecting settlement resumes card play")
    func rejectingSettlementResumesCardPlay() throws {
        var engine = try makeMisereEngine()
        let settlement = try #require(engine.legalSettlements(for: "north").first)

        _ = try engine.apply(.proposeSettlement(player: "north", settlement: settlement))
        let events = try engine.apply(.rejectSettlement(player: "east"))

        #expect(events == [.settlementRejected(player: "east")])
        guard case let .playing(playing) = engine.state else {
            Issue.record("Expected card play to resume.")
            return
        }
        #expect(playing.pendingSettlement == nil)
        #expect(!engine.legalCards(for: playing.currentPlayer).isEmpty)
    }

    @Test("Settlement rejects impossible final counts")
    func settlementRejectsImpossibleFinalCounts() throws {
        var engine = try makeMisereEngine()
        let invalid = TrickSettlement(
            target: "north",
            targetTricks: 6,
            finalTrickCounts: ["north": 6, "east": 2, "south": 1]
        )

        #expect {
            try engine.apply(.proposeSettlement(player: "north", settlement: invalid))
        } throws: { error in
            (error as? PreferansError) == .illegalSettlement("Settlement final trick counts must total 10.")
        }
    }

    @Test("Open game lets the declarer and whisters offer, but not a passed defender")
    func openGameSettlementRoleGating() throws {
        // east declares, south whists (open), north passed out of the whist.
        let engine = try makeOpenGameEngine()
        #expect(!engine.legalSettlements(for: "east").isEmpty, "The declarer may offer in an open game.")
        #expect(!engine.legalSettlements(for: "south").isEmpty, "A whister may offer in an open game.")
        #expect(engine.legalSettlements(for: "north").isEmpty, "A passed defender may not offer.")
    }

    @Test("Misère lets the declarer and every defender offer")
    func misereSettlementRoleGating() throws {
        let engine = try makeMisereEngine()
        for player in players {
            #expect(!engine.legalSettlements(for: player).isEmpty, "\(player) may offer a settlement in a misère.")
        }
    }

    @Test("Closed game never offers a settlement")
    func closedGameOffersNoSettlement() throws {
        // A two-whister game is always played closed.
        let engine = try makeGamePlayingEngine()
        for player in players {
            #expect(engine.legalSettlements(for: player).isEmpty, "\(player) must not be able to settle a closed game.")
        }
    }

    @Test("All-pass deals are played out, never settled")
    func allPassOffersNoSettlement() throws {
        let engine = try makeAllPassEngine()
        for player in players {
            #expect(engine.legalSettlements(for: player).isEmpty, "\(player) must not be able to settle an all-pass deal.")
        }
    }

    @Test("Proposing a settlement in a closed game is rejected")
    func proposingInClosedGameRejected() throws {
        var engine = try makeGamePlayingEngine()
        // Structurally valid (totals 10, takes nothing back), but a closed
        // game is ineligible for settlement regardless of who offers.
        let structurallyValid = TrickSettlement(
            target: "east",
            targetTricks: 6,
            finalTrickCounts: ["east": 6, "south": 2, "north": 2]
        )

        #expect {
            try engine.apply(.proposeSettlement(player: "east", settlement: structurallyValid))
        } throws: { error in
            (error as? PreferansError) == .illegalSettlement(
                "Only the declarer or a whister may offer a settlement, and only in an open game or misère."
            )
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
        var engine = try makeMisereEngine()
        let settlement = try #require(engine.legalSettlements(for: "north").first)
        _ = try engine.apply(.proposeSettlement(player: "north", settlement: settlement))

        let eastProjection = PlayerProjectionBuilder.projection(
            for: "east",
            tableID: UUID(),
            sequence: 1,
            engine: engine,
            policy: .online
        )
        #expect(eastProjection.legal.pendingSettlement?.settlement == settlement)
        #expect(eastProjection.legal.canAcceptSettlement)
        #expect(eastProjection.legal.canRejectSettlement)

        let northProjection = PlayerProjectionBuilder.projection(
            for: "north",
            tableID: UUID(),
            sequence: 1,
            engine: engine,
            policy: .online
        )
        // The proposer auto-accepts, so they can only cancel by rejecting.
        #expect(!northProjection.legal.canAcceptSettlement)
        #expect(northProjection.legal.canRejectSettlement)
    }

    @Test("Bot plays deterministic last trick instead of proposing settlement")
    func botPlaysDeterministicLastTrick() async throws {
        let strategy = HeuristicStrategy(planner: CardPlayPlanner(samples: 1, rolloutsPerSample: 1))
        var engine = try makeLastTrickEngine()

        let drive = try await BotTestDriver.drive(engine: &engine, strategy: strategy, stepLimit: 4)

        #expect(!drive.stalled, "Bots should play the deterministic last trick.")
        #expect(drive.steps == 3)
        guard case let .dealFinished(result) = engine.state else {
            Issue.record("Expected the played last trick to finish the deal.")
            return
        }
        #expect(result.settlement == nil)
        #expect(result.completedTricks.count == 10)
        #expect(result.trickCounts.values.reduce(0, +) == 10)
    }

    // MARK: - Fixtures

    /// A closed two-whister game at the opening lead. Two whisters always
    /// play closed, so this fixture is never eligible for settlement —
    /// used by the closed-game exclusion tests and as the basis for the
    /// forced last-trick fixture below.
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

    /// The closed game wound forward to its final, fully forced trick.
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

    /// A misère at the opening lead — every active seat may offer.
    private func makeMisereEngine() throws -> PreferansEngine {
        try playingEngine(kind: .misere(MiserePlayContext(declarer: "north")))
    }

    /// A single-whister game played open. east declares; south is the lone
    /// whister; north passed and so cannot offer a settlement.
    private func makeOpenGameEngine() throws -> PreferansEngine {
        try playingEngine(kind: .game(GamePlayContext(
            declarer: "east",
            contract: GameContract(6, .suit(.clubs)),
            defenders: ["north", "south"],
            whisters: ["south"],
            defenderPlayMode: .open,
            whistCalls: []
        )))
    }

    /// An all-pass deal — ineligible for settlement.
    private func makeAllPassEngine() throws -> PreferansEngine {
        try playingEngine(kind: .allPass(AllPassPlayContext(talonPolicy: .ignored)))
    }

    /// Builds a fresh `.playing` engine in the requested play kind, dealt
    /// from a clean deck at the opening lead (no tricks played). The
    /// discard mirrors the engine's invariants: two cards in game/misère,
    /// empty for all-pass.
    private func playingEngine(kind: PlayKind) throws -> PreferansEngine {
        let deal = DealDeckLayout.deal(deck: Deck.standard32, activePlayers: players)
        let discard: [Card]
        if case .allPass = kind {
            discard = []
        } else {
            discard = deal.talon
        }
        let playing = PlayingState(
            dealer: "south",
            activePlayers: players,
            hands: deal.hands,
            talon: deal.talon,
            discard: discard,
            leader: players[0],
            currentPlayer: players[0],
            kind: kind
        )
        return try PreferansEngine(
            snapshot: PreferansSnapshot(
                players: players,
                rules: .sochi,
                state: .playing(playing),
                score: ScoreSheet(players: players),
                nextDealer: "north"
            )
        )
    }
}
