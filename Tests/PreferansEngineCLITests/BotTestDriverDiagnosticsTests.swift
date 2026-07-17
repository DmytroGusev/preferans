import Foundation
import Testing
@testable import PreferansEngine
@testable import PreferansEngineTestSupport

@Suite("Bot test-driver diagnostics")
struct BotTestDriverDiagnosticsTests {
    @Test("Completion on the exact action bound is not reported as a stall")
    func exactStepLimitCompletion() async throws {
        var engine = try makeAllPassEngine()
        try advanceLowestLegalCards(in: &engine, count: 27)

        let result = try await BotTestDriver.drive(
            engine: &engine,
            strategy: LowestLegalCardStrategy(),
            stepLimit: 3
        )

        #expect(result == BotDriveResult(steps: 3, stopReason: .phaseCompleted))
        #expect(!result.stalled)
        #expect(result.illegalActionAttempts == 0)
        if case .dealFinished = engine.state {
            // Expected terminal state for the unbounded match fixture.
        } else {
            Issue.record("Expected dealFinished, got \(engine.state.description)")
        }
    }

    @Test("A live phase at the action bound reports its next actor")
    func stepLimitDiagnosis() async throws {
        var engine = try makeAllPassEngine()

        let result = try await BotTestDriver.drive(
            engine: &engine,
            strategy: LowestLegalCardStrategy(),
            stepLimit: 1
        )

        #expect(result.steps == 1)
        #expect(result.stalled)
        #expect(result.illegalActionAttempts == 0)
        guard let nextActor = engine.state.currentActor else {
            Issue.record("Expected all-pass play to remain active after one card")
            return
        }
        #expect(
            result.stopReason == .stepLimitReached(
                limit: 1,
                actor: nextActor,
                decider: engine.controllingActor(of: nextActor)
            )
        )
    }

    @Test("A refusal identifies both the acting seat and deciding seat")
    func nilActionDiagnosis() async throws {
        var engine = try PreferansEngine(players: ["N", "E", "S"], firstDealer: "S")
        _ = try engine.startDeal(deck: Deck.standard32)

        let result = try await BotTestDriver.drive(
            engine: &engine,
            strategy: RefusingStrategy()
        )

        #expect(result.steps == 0)
        #expect(result.stopReason == .strategyReturnedNoAction(actor: "N", decider: "N"))
        #expect(result.stalled)
        #expect(result.illegalActionAttempts == 0)
    }

    @Test("A rejected action preserves the decision context and engine error")
    func rejectedActionDiagnosis() async throws {
        var engine = try PreferansEngine(players: ["N", "E", "S"], firstDealer: "S")
        _ = try engine.startDeal(deck: Deck.standard32)
        let rejectedAction = PreferansAction.bid(player: "E", call: .pass)

        let result = try await BotTestDriver.drive(
            engine: &engine,
            strategy: WrongSeatBidStrategy()
        )

        #expect(result.steps == 0)
        #expect(result.stalled)
        #expect(result.illegalActionAttempts == 1)
        guard case let .engineRejectedAction(actor, decider, action, error) = result.stopReason else {
            Issue.record("Expected an engine-rejected-action diagnosis, got \(result.stopReason)")
            return
        }
        #expect(actor == "N")
        #expect(decider == "N")
        #expect(action == rejectedAction)
        #expect(error.contains("Expected N"))
    }

    private func makeAllPassEngine() throws -> PreferansEngine {
        var engine = try PreferansEngine(players: ["N", "E", "S"], firstDealer: "S")
        _ = try engine.startDeal(deck: Deck.standard32)
        while case let .bidding(state) = engine.state {
            _ = try engine.apply(.bid(player: state.currentPlayer, call: .pass))
        }
        return engine
    }

    private func advanceLowestLegalCards(
        in engine: inout PreferansEngine,
        count: Int
    ) throws {
        for _ in 0..<count {
            guard case let .playing(state) = engine.state,
                  let card = engine.legalCards(for: state.currentPlayer).min()
            else {
                throw EngineTestError("Expected a legal card while preparing the boundary fixture.")
            }
            _ = try engine.apply(.playCard(player: state.currentPlayer, card: card))
        }
    }
}

private struct LowestLegalCardStrategy: PlayerStrategy {
    func decide(snapshot: PreferansSnapshot, viewer: PlayerID) async -> PreferansAction? {
        guard let engine = try? PreferansEngine(snapshot: snapshot),
              let actor = snapshot.state.currentActor,
              engine.controllingActor(of: actor) == viewer,
              let card = engine.legalCards(for: viewer).min()
        else {
            return nil
        }
        return .playCard(player: actor, card: card)
    }
}

private struct RefusingStrategy: PlayerStrategy {
    func decide(snapshot: PreferansSnapshot, viewer: PlayerID) async -> PreferansAction? {
        nil
    }
}

private struct WrongSeatBidStrategy: PlayerStrategy {
    func decide(snapshot: PreferansSnapshot, viewer: PlayerID) async -> PreferansAction? {
        .bid(player: "E", call: .pass)
    }
}
