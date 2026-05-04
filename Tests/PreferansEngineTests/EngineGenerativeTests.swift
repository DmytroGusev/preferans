import XCTest
@testable import PreferansEngine

final class EngineGenerativeTests: XCTestCase {
    func testSeededLegalActionWalksMaintainInvariantsAndCodableSnapshots() throws {
        let cases: [(players: [PlayerID], firstDealer: PlayerID, rules: PreferansRules)] = [
            (["north", "east", "south"], "south", .sochi),
            (["north", "east", "south", "west"], "west", .sochiWithTalonLedAllPass)
        ]

        for testCase in cases {
            for seed in UInt64(1)...UInt64(18) {
                var rng = SeededRandomNumberGenerator(seed: seed)
                var engine = try PreferansEngine(
                    players: testCase.players,
                    rules: testCase.rules,
                    firstDealer: testCase.firstDealer
                )

                for step in 0..<180 {
                    try assertSnapshotIsValidAndCodable(engine.snapshot, seed: seed, step: step)
                    guard let action = try nextLegalAction(engine: engine, rng: &rng) else { break }
                    _ = try engine.apply(action)
                }

                try assertSnapshotIsValidAndCodable(engine.snapshot, seed: seed, step: 180)
            }
        }
    }

    private func nextLegalAction(
        engine: PreferansEngine,
        rng: inout SeededRandomNumberGenerator
    ) throws -> PreferansAction? {
        switch engine.state {
        case .waitingForDeal, .dealFinished:
            return .startDeal(dealer: nil, deck: Deck.standard32.shuffled(using: &rng))

        case .gameOver:
            return nil

        case let .bidding(state):
            let calls = engine.legalBidCalls(for: state.currentPlayer)
            return .bid(player: state.currentPlayer, call: try choose(calls, rng: &rng, context: "bid calls"))

        case let .awaitingDiscard(state):
            let hand = state.hands[state.declarer] ?? []
            let discard = Array(hand.shuffled(using: &rng).prefix(2))
            return .discard(player: state.declarer, cards: discard)

        case let .awaitingContract(state):
            let contracts = engine.legalContractDeclarations(for: state.declarer)
            return .declareContract(
                player: state.declarer,
                contract: try choose(contracts, rng: &rng, context: "contract declarations")
            )

        case let .awaitingWhist(state):
            let calls = engine.legalWhistCalls(for: state.currentPlayer)
            return .whist(player: state.currentPlayer, call: try choose(calls, rng: &rng, context: "whist calls"))

        case let .awaitingDefenderMode(state):
            let modes: [DefenderPlayMode] = [.closed, .open]
            return .chooseDefenderMode(player: state.whister, mode: try choose(modes, rng: &rng, context: "defender modes"))

        case let .playing(state):
            if let proposal = state.pendingSettlement {
                let pending = state.activePlayers.filter { !proposal.acceptedBy.contains($0) }
                if let responder = pending.first {
                    return Bool.random(using: &rng)
                        ? .acceptSettlement(player: responder)
                        : .rejectSettlement(player: responder)
                }
                return nil
            }

            let cards = engine.legalCards(for: state.currentPlayer)
            return .playCard(player: state.currentPlayer, card: try choose(cards, rng: &rng, context: "legal cards"))
        }
    }

    private func assertSnapshotIsValidAndCodable(
        _ snapshot: PreferansSnapshot,
        seed: UInt64,
        step: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        do {
            try PreferansEngine.validateInvariants(snapshot)
            let data = try JSONEncoder().encode(snapshot)
            let decoded = try JSONDecoder().decode(PreferansSnapshot.self, from: data)
            let restored = try PreferansEngine(snapshot: decoded)
            XCTAssertEqual(restored.snapshot, snapshot, "seed \(seed), step \(step)", file: file, line: line)
        } catch {
            XCTFail("seed \(seed), step \(step): \(error)", file: file, line: line)
            throw error
        }
    }

    private func choose<T>(
        _ values: [T],
        rng: inout SeededRandomNumberGenerator,
        context: String
    ) throws -> T {
        guard let value = values.randomElement(using: &rng) else {
            throw EngineTestError("No generated choice for \(context).")
        }
        return value
    }
}
