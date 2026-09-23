import Foundation
import Testing
@testable import PreferansEngine

@Suite("Misere opening visibility")
struct MisereVisibilityTests {
    @Test(arguments: [3, 4])
    func declarerLeads(count: Int) throws {
        var engine = try makeEngine(count: count, declarerLeads: true)
        try check(engine, opened: false)
        let card = try #require(engine.legalCards(for: "north").first)
        _ = try engine.apply(.playCard(player: "north", card: card))
        try check(engine, opened: true)
        // The reveal persists through the end of the first trick and later leads.
        for _ in 0..<2 {
            let actor = try #require(engine.state.currentActor)
            let next = try #require(engine.legalCards(for: actor).first)
            _ = try engine.apply(.playCard(player: actor, card: next))
        }
        try check(engine, opened: true)
        let restored = try PreferansEngine(snapshot: JSONDecoder().decode(
            PreferansSnapshot.self, from: JSONEncoder().encode(engine.snapshot)
        ))
        try check(restored, opened: true)
    }

    @Test(arguments: [3, 4])
    func defenderLeads(count: Int) throws {
        try check(makeEngine(count: count, declarerLeads: false), opened: true)
    }

    @Test
    func botCannotSeeDefendersBeforeOpeningLead() throws {
        var engine = try makeEngine(count: 3, declarerLeads: true)
        var rng = SeededRandomNumberGenerator(seed: 28)
        let hidden = DealSampler().samples(from: engine.snapshot, viewer: "north", count: 12, rng: &rng)
        #expect(hidden.count == 12)
        guard case let .playing(original) = engine.state else { return }
        #expect(hidden.contains { sample in
            guard case let .playing(state) = sample.state else { return false }
            return state.hands["east"] != original.hands["east"]
        })
        _ = try engine.apply(.playCard(player: "north", card: #require(engine.legalCards(for: "north").first)))
        guard case let .playing(opened) = engine.state else { return }
        let samples = DealSampler().samples(from: engine.snapshot, viewer: "north", count: 4, rng: &rng)
        #expect(samples.count == 4)
        for sample in samples {
            guard case let .playing(state) = sample.state else { continue }
            #expect(state.hands["east"] == opened.hands["east"])
            #expect(state.hands["south"] == opened.hands["south"])
        }
    }

    private func makeEngine(count: Int, declarerLeads: Bool) throws -> PreferansEngine {
        let active: [PlayerID] = declarerLeads ? ["north", "east", "south"] : ["east", "south", "north"]
        let players = count == 4 ? active + ["west"] : active
        let deal = DealDeckLayout.deal(deck: Deck.standard32, activePlayers: active)
        let leader: PlayerID = declarerLeads ? "north" : "east"
        let state = PlayingState(dealer: count == 4 ? "west" : active[2],
            activePlayers: active, hands: deal.hands, talon: deal.talon,
            discard: deal.talon, leader: leader, currentPlayer: leader,
            kind: .misere(MiserePlayContext(declarer: "north")))
        return try PreferansEngine(snapshot: PreferansSnapshot(players: players,
            rules: .sochi, state: .playing(state), score: ScoreSheet(players: players),
            nextDealer: active[0]))
    }

    private func check(_ engine: PreferansEngine, opened: Bool) throws {
        guard case let .playing(state) = engine.state else {
            Issue.record("Expected playing state")
            return
        }
        #expect(state.misereDefendersAreOpen == opened)
        for viewer in engine.players {
            let projection = PlayerProjectionBuilder.projection(for: viewer,
                tableID: UUID(), sequence: 0, engine: engine, policy: .online)
            for seat in projection.seats {
                let visible = seat.player == viewer || (opened && seat.player != "north")
                #expect(seat.hand.compactMap(\.knownCard).count == (visible ? seat.hand.count : 0))
            }
            #expect(projection.discard.compactMap(\.knownCard).count == (viewer == "north" ? 2 : 0))
        }
    }
}
