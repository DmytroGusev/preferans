import XCTest
@testable import PreferansEngine

final class BotInformationTests: XCTestCase {
    private let active: [PlayerID] = ["north", "east", "south"]

    func testRolloutCardsMatchValidatedPlayThroughCompleteDeals() throws {
        for kind in [game(), PlayKind.allPass(.init(talonPolicy: .ignored))] {
            var checked = try PreferansEngine(snapshot: makeSnapshot(kind: kind))
            var rollout = checked
            var count = 0
            while case let .playing(state) = checked.state {
                let actor = state.currentPlayer
                let controller = checked.controllingActor(of: actor)
                let card = try XCTUnwrap(checked.legalCards(for: controller).first)
                if count == 0 {
                    let wrongActor = try XCTUnwrap(active.first { $0 != actor })
                    XCTAssertThrowsError(try rollout.applyRolloutCard(player: wrongActor, card: card))
                    XCTAssertEqual(rollout.snapshot, checked.snapshot)
                }
                _ = try checked.apply(.playCard(player: actor, card: card))
                try rollout.applyRolloutCard(player: actor, card: card)
                XCTAssertEqual(rollout.snapshot, checked.snapshot)
                count += 1
            }
            XCTAssertEqual(count, 30)
        }
    }

    func testClosedGameSamplesRespectThePublicExchangeAndRehydrate() throws {
        let snapshot = makeSnapshot(kind: game())
        let worlds = sampled(snapshot, viewer: "north", count: 64)
        XCTAssertEqual(worlds.count, 64)
        var eastHands = Set<[Card]>()
        for world in worlds {
            XCTAssertNoThrow(try PreferansEngine(snapshot: world))
            let state = try playing(world)
            XCTAssertEqual(state.hands["north"], try playing(snapshot).hands["north"])
            let traceable = Set((state.hands["east"] ?? []) + state.discard)
            XCTAssertTrue(Set(state.talon).isSubset(of: traceable))
            eastHands.insert(state.hands["east"] ?? [])
        }
        XCTAssertGreaterThan(eastHands.count, 20, "Hidden worlds must vary rather than reproduce the real deal")
    }

    func testAnEmptySampleSetUsesOnlyTheViewersLegalCards() throws {
        let snapshot = makeSnapshot(kind: game())
        var state = try playing(snapshot)
        let east = state.hands["east"]
        state.hands["east"] = state.hands["south"]
        state.hands["south"] = east
        var alternative = snapshot
        alternative.state = .playing(state)
        let legal = try PreferansEngine(snapshot: snapshot).legalCards(for: "north")
        XCTAssertNoThrow(try PreferansEngine(snapshot: alternative))
        var planner = CardPlayPlanner(samples: 1)
        planner.samples = 0 // Exercise the same empty result as an unsuccessful sampler.
        XCTAssertEqual(planner.choose(snapshot: snapshot, viewer: "north"), legal.min())
        XCTAssertEqual(planner.choose(snapshot: alternative, viewer: "north"), legal.min())
    }

    func testHiddenTalonWorldsAndDecisionsIgnoreTheRealHiddenCards() throws {
        let snapshot = makeSnapshot(kind: .allPass(.init(talonPolicy: .ignored)))
        let original = try playing(snapshot)
        var hands = original.hands
        var talon = original.talon
        let swap = hands["east"]![0]
        hands["east"]![0] = talon[0]
        talon[0] = swap
        let alternative = replacing(snapshot, hands: hands, talon: talon)
        XCTAssertNoThrow(try PreferansEngine(snapshot: alternative))
        let first = sampled(snapshot, viewer: "north")
        let second = sampled(alternative, viewer: "north")
        XCTAssertEqual(first.count, 16)
        XCTAssertEqual(first, second, "Indistinguishable hidden deals must produce identical sampled worlds")
        XCTAssertGreaterThan(Set(try first.map { try playing($0).talon }).count, 1)
        for world in first { XCTAssertNoThrow(try PreferansEngine(snapshot: world)) }
        let planner = CardPlayPlanner(samples: 4)
        XCTAssertEqual(planner.choose(snapshot: snapshot, viewer: "north"),
                       planner.choose(snapshot: alternative, viewer: "north"))
    }

    func testFirstRaspasyLeadKeepsOnlyTheRevealedTalonCardFixed() throws {
        let snapshot = makeSnapshot(kind: .allPass(.init(talonPolicy: .classic)), fourSeats: true)
        let original = try playing(snapshot)
        let worlds = sampled(snapshot, viewer: "north")
        XCTAssertEqual(worlds.count, 16)
        for world in worlds {
            XCTAssertNoThrow(try PreferansEngine(snapshot: world))
            XCTAssertEqual(try playing(world).talon.first, original.talon.first)
        }
        XCTAssertGreaterThan(Set(try worlds.map { try playing($0).talon[1] }).count, 1)
    }

    func testRevealedRaspasyLeadsRemainKnownAfterBothOpeningTricks() throws {
        var engine = try PreferansEngine(snapshot: makeSnapshot(
            kind: .allPass(.init(talonPolicy: .classic)), fourSeats: true
        ))
        for _ in 0..<6 {
            let state = try playing(engine.snapshot)
            let card = try XCTUnwrap(engine.legalCards(for: state.currentPlayer).first)
            _ = try engine.apply(.playCard(player: state.currentPlayer, card: card))
        }
        let original = try playing(engine.snapshot)
        let worlds = sampled(engine.snapshot, viewer: "north")
        XCTAssertEqual(worlds.count, 16)
        for world in worlds {
            XCTAssertNoThrow(try PreferansEngine(snapshot: world))
            XCTAssertEqual(try playing(world).talon, original.talon)
        }
    }

    func testOpenDefenseKeepsBothDefendersVisibleToEverySeat() throws {
        let snapshot = makeSnapshot(kind: game(open: true))
        for viewer in active {
            let worlds = sampled(snapshot, viewer: viewer)
            XCTAssertEqual(worlds.count, 16)
            for world in worlds {
                XCTAssertNoThrow(try PreferansEngine(snapshot: world))
                for owner: PlayerID in ["north", "south", viewer] {
                    XCTAssertEqual(try playing(world).hands[owner], try playing(snapshot).hands[owner])
                }
            }
        }
    }

    func testTenTrickVerificationKeepsEveryHandVisible() throws {
        let snapshot = makeSnapshot(kind: game(ten: true))
        for world in sampled(snapshot, viewer: "north") {
            XCTAssertNoThrow(try PreferansEngine(snapshot: world))
            XCTAssertEqual(try playing(world).hands, try playing(snapshot).hands)
        }
    }

    func testOffSuitForehandIsKnownVoidInTheTalonLeadSuit() throws {
        for four in [false, true] {
            let base = makeSnapshot(kind: .allPass(.init(talonPolicy: .classic)), fourSeats: four)
            let talon = [Card(.spades, .ace), Card(.spades, .king)]
            let north = Deck.standard32.filter { $0.suit == .hearts }
                + [Card(.clubs, .seven), Card(.clubs, .eight)]
            let remaining = Deck.standard32.filter { !Set(talon + north).contains($0) }
            let hands: [PlayerID: [Card]] = [
                "north": north, "east": Array(remaining.prefix(10)), "south": Array(remaining.suffix(10))
            ]
            var engine = try PreferansEngine(snapshot: replacing(base, hands: hands, talon: talon))
            _ = try engine.apply(.playCard(player: "north", card: Card(.hearts, .seven)))
            let state = try playing(engine.snapshot)
            XCTAssertEqual(state.requiredSuit, .spades)
            XCTAssertEqual(DealSampler().inferredVoids(in: state)["north"], [.spades])
            for world in sampled(engine.snapshot, viewer: "east") {
                XCTAssertNoThrow(try PreferansEngine(snapshot: world))
                XCTAssertFalse(try playing(world).hands["north"]!.contains { $0.suit == .spades })
            }
        }
    }

    private func sampled(_ snapshot: PreferansSnapshot, viewer: PlayerID, count: Int = 16) -> [PreferansSnapshot] {
        var rng = SeededRandomNumberGenerator(seed: 20260908)
        return DealSampler().samples(from: snapshot, viewer: viewer, count: count, rng: &rng)
    }

    private func game(open: Bool = false, ten: Bool = false) -> PlayKind {
        .game(.init(declarer: "east", contract: GameContract(ten ? 10 : 6, .suit(.clubs)),
                    defenders: ["north", "south"], whisters: ten ? [] : (open ? ["north"] : ["north", "south"]),
                    defenderPlayMode: open || ten ? .open : .closed, whistCalls: []))
    }

    private func makeSnapshot(kind: PlayKind, fourSeats: Bool = false) -> PreferansSnapshot {
        let deal = DealDeckLayout.deal(deck: Deck.standard32, activePlayers: active)
        let allPass: Bool = { if case .allPass = kind { true } else { false } }()
        let state = PlayingState(
            dealer: fourSeats ? "west" : "south", activePlayers: active,
            hands: deal.hands, talon: deal.talon, discard: allPass ? [] : deal.talon,
            leader: fourSeats && allPass ? "west" : "north", currentPlayer: "north", kind: kind
        )
        let players: [PlayerID] = fourSeats ? active + ["west"] : active
        var rules = PreferansRules.sochi
        if case let .allPass(context) = kind { rules.allPassTalonPolicy = context.talonPolicy }
        return PreferansSnapshot(players: players, rules: rules, state: .playing(state),
                                 score: ScoreSheet(players: players), nextDealer: "north")
    }

    private func playing(_ snapshot: PreferansSnapshot) throws -> PlayingState {
        guard case let .playing(state) = snapshot.state else { throw NSError(domain: "Expected playing", code: 1) }
        return state
    }

    private func replacing(_ snapshot: PreferansSnapshot, hands: [PlayerID: [Card]], talon: [Card]) -> PreferansSnapshot {
        guard case let .playing(state) = snapshot.state else { return snapshot }
        var updated = snapshot
        updated.state = .playing(PlayingState(
            dealer: state.dealer, activePlayers: state.activePlayers, hands: hands,
            talon: talon, discard: state.discard, leader: state.leader, currentPlayer: state.currentPlayer,
            currentTrick: state.currentTrick, completedTricks: state.completedTricks,
            trickCounts: state.trickCounts, kind: state.kind
        ))
        return updated
    }
}
