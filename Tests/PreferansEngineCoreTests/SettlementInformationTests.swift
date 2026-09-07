import XCTest
@testable import PreferansEngine

final class SettlementInformationTests: XCTestCase {
    private let players: [PlayerID] = ["north", "east", "south"]
    private var kinds: [PlayKind] {
        [
            .misere(.init(declarer: "north")),
            .game(.init(declarer: "north", contract: GameContract(6, .noTrump),
                        defenders: ["east", "south"], whisters: ["east"],
                        defenderPlayMode: .open, whistCalls: []))
        ]
    }

    func testLastTrickSuggestionsDoNotExposeTheDeclarersHiddenCard() throws {
        for kind in kinds {
            let first = try lastTrick(kind: kind)
            let second = try swappingHiddenQueenAndAce(in: first)
            let state = try playing(first)
            let alternative = try playing(second)
            XCTAssertEqual(state.hands["east"], [Card(.hearts, .ten)])
            XCTAssertEqual(state.hands["south"], [Card(.hearts, .king)])
            XCTAssertEqual(state.hands["north"], [Card(.hearts, .queen)])
            XCTAssertEqual(alternative.hands["north"], [Card(.hearts, .ace)])
            XCTAssertEqual(state.leader, "south")
            let queenOutcome = try XCTUnwrap(first.forcedSettlement(in: state))
            let aceOutcome = try XCTUnwrap(second.forcedSettlement(in: alternative))
            XCTAssertEqual(queenOutcome.finalTrickCounts["south"], state.trickCounts["south"]! + 1)
            XCTAssertEqual(aceOutcome.finalTrickCounts["north"], state.trickCounts["north"]! + 1)

            let tableID = UUID()
            let firstProjection = PlayerProjectionBuilder.projection(
                for: "east", tableID: tableID, sequence: 27, engine: first, policy: .online
            )
            let secondProjection = PlayerProjectionBuilder.projection(
                for: "east", tableID: tableID, sequence: 27, engine: second, policy: .online
            )
            XCTAssertEqual(firstProjection.seats, secondProjection.seats)
            XCTAssertEqual(firstProjection.legal.settlementOptions, secondProjection.legal.settlementOptions,
                           "A suggested split must not reveal whether the hidden last card is the ace")
        }
    }

    func testBotRejectsAnUncertainFinalSplitInBothHiddenWorlds() async throws {
        for kind in kinds {
            let first = try lastTrick(kind: kind)
            let settlement = try XCTUnwrap(first.forcedSettlement(in: playing(first)))
            for var engine in [first, try swappingHiddenQueenAndAce(in: first)] {
                _ = try engine.apply(.proposeSettlement(player: "north", settlement: settlement))
                XCTAssertEqual(engine.state.currentActor, "east")
                let decision = await HeuristicStrategy().decide(snapshot: engine.snapshot, viewer: "east")
                XCTAssertEqual(decision, .rejectSettlement(player: "east"),
                               "A defender cannot know whether north kept the queen or ace of hearts")
            }
        }
    }

    func testDeclarerCanUseEveryExposedHandAndTheirOwnDiscard() throws {
        for kind in kinds {
            let first = try lastTrick(kind: kind)
            for engine in [first, try swappingHiddenQueenAndAce(in: first)] {
                let state = try playing(engine)
                XCTAssertEqual(engine.forcedSettlement(in: state, knownTo: "north"),
                               engine.forcedSettlement(in: state))
                XCTAssertNil(engine.forcedSettlement(in: state, knownTo: "east"))
            }
        }
    }

    func testDefenderAcceptsWhenEveryPossibleHiddenCardLoses() async throws {
        for kind in kinds {
            var engine = try lastTrick(kind: kind, defenderHasAce: true)
            let state = try playing(engine)
            // South's exposed A♥ beats each possible concealed Q♥ / K♥ / 7♥.
            let forced = try XCTUnwrap(engine.forcedSettlement(in: state, knownTo: "east"))
            XCTAssertEqual(forced.finalTrickCounts["south"], state.trickCounts["south"]! + 1)
            _ = try engine.apply(.proposeSettlement(player: "north", settlement: forced))
            let decision = await HeuristicStrategy().decide(snapshot: engine.snapshot, viewer: "east")
            XCTAssertEqual(decision, .acceptSettlement(player: "east"))
        }
    }

    func testTenTrickVerificationUsesTheDeclarersExposedHand() throws {
        let kind = PlayKind.game(.init(declarer: "north", contract: GameContract(10, .noTrump),
                                      defenders: ["east", "south"], whisters: [],
                                      defenderPlayMode: .open, whistCalls: []))
        let engine = try lastTrick(kind: kind)
        let state = try playing(engine)
        for viewer in players {
            XCTAssertEqual(engine.forcedSettlement(in: state, knownTo: viewer),
                           engine.forcedSettlement(in: state))
        }
    }

    /// Nine legal tricks leave Q♥ / 10♥ / K♥, with south on lead. A♥ and
    /// 7♥ were the public talon and are now north's private discard. Swapping
    /// Q♥ with A♥ preserves every observed play while changing the winner.
    private func lastTrick(kind: PlayKind, defenderHasAce: Bool = false) throws -> PreferansEngine {
        var hands: [PlayerID: [Card]] = [
            "north": [.init(.spades, .ten), .init(.spades, .ace), .init(.hearts, .queen),
                      .init(.diamonds, .jack), .init(.diamonds, .ten), .init(.spades, .queen),
                      .init(.spades, .seven), .init(.clubs, .nine), .init(.clubs, .king), .init(.hearts, .nine)],
            "east": [.init(.diamonds, .eight), .init(.diamonds, .queen), .init(.hearts, .ten),
                     .init(.diamonds, .ace), .init(.spades, .nine), .init(.diamonds, .king),
                     .init(.spades, .jack), .init(.hearts, .eight), .init(.spades, .king), .init(.diamonds, .nine)],
            "south": [.init(.clubs, .ten), .init(.hearts, .king), .init(.clubs, .eight),
                      .init(.clubs, .jack), .init(.clubs, .ace), .init(.diamonds, .seven),
                      .init(.clubs, .seven), .init(.spades, .eight), .init(.clubs, .queen), .init(.hearts, .jack)]
        ]
        var talon = [Card(.hearts, .ace), Card(.hearts, .seven)]
        if defenderHasAce {
            hands["south"] = hands["south"]?.map {
                $0 == Card(.hearts, .king) ? Card(.hearts, .ace) : $0
            }
            talon = [Card(.hearts, .king), Card(.hearts, .seven)]
        }
        let state = PlayingState(dealer: "south", activePlayers: players, hands: hands,
                                 talon: talon, discard: talon, leader: "north", currentPlayer: "north", kind: kind)
        var engine = try PreferansEngine(snapshot: .init(
            players: players, rules: .sochi, state: .playing(state),
            score: ScoreSheet(players: players), nextDealer: "north"
        ))
        for _ in 0..<27 {
            let state = try playing(engine)
            let controller = engine.controllingActor(of: state.currentPlayer)
            let card = try XCTUnwrap(engine.legalCards(for: controller).min())
            _ = try engine.apply(.playCard(player: state.currentPlayer, card: card))
        }
        return engine
    }

    private func swappingHiddenQueenAndAce(in engine: PreferansEngine) throws -> PreferansEngine {
        var state = try playing(engine)
        state.hands["north"] = [Card(.hearts, .ace)]
        state.discard = [Card(.hearts, .queen), Card(.hearts, .seven)]
        var snapshot = engine.snapshot
        snapshot.state = .playing(state)
        return try PreferansEngine(snapshot: snapshot)
    }

    private func playing(_ engine: PreferansEngine) throws -> PlayingState {
        guard case let .playing(state) = engine.state else {
            throw NSError(domain: "Expected playing state", code: 1)
        }
        return state
    }
}
