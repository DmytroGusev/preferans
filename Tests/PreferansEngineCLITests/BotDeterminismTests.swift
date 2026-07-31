import Testing
@testable import PreferansEngine

@Suite("Bot determinism")
struct BotDeterminismTests {
    @Test("Deal sampler returns equal samples for equal seeds")
    func equalSeedSampler() {
        let snapshot = makePlayingSnapshot()
        let sampler = DealSampler()
        var firstRNG = SeededRandomNumberGenerator(seed: 0x5A4D_504C_4552)
        var secondRNG = SeededRandomNumberGenerator(seed: 0x5A4D_504C_4552)

        let first = sampler.samples(from: snapshot, viewer: "north", count: 8, rng: &firstRNG)
        let second = sampler.samples(from: snapshot, viewer: "north", count: 8, rng: &secondRNG)

        #expect(first.count == 8)
        #expect(first == second)
    }

    @Test("Card planner is pure for a snapshot, viewer, and configuration")
    func plannerPurity() {
        let snapshot = makePlayingSnapshot()
        let planner = CardPlayPlanner(
            samples: 8,
            samplingSeed: 0x504C_414E_4E45_52
        )

        let first = planner.choose(snapshot: snapshot, viewer: "north")

        #expect(first != nil)
        for _ in 0..<4 {
            #expect(planner.choose(snapshot: snapshot, viewer: "north") == first)
        }
    }

    private func makePlayingSnapshot() -> PreferansSnapshot {
        let players: [PlayerID] = ["north", "east", "south"]
        let deal = DealDeckLayout.deal(deck: Deck.standard32, activePlayers: players)
        let playing = PlayingState(
            dealer: "south",
            activePlayers: players,
            hands: deal.hands,
            talon: deal.talon,
            discard: deal.talon,
            leader: "north",
            currentPlayer: "north",
            kind: .game(GamePlayContext(
                declarer: "east",
                contract: GameContract(6, .suit(.clubs)),
                defenders: ["north", "south"],
                whisters: ["north", "south"],
                defenderPlayMode: .closed,
                whistCalls: []
            ))
        )
        return PreferansSnapshot(
            players: players,
            rules: .sochi,
            state: .playing(playing),
            score: ScoreSheet(players: players),
            nextDealer: "north"
        )
    }
}
