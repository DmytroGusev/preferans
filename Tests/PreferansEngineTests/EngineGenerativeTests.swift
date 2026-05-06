import Foundation
import Testing
@testable import PreferansEngine

@Suite("Engine generative walks")
struct EngineGenerativeTests {
    struct Config: CustomTestStringConvertible {
        let players: [PlayerID]
        let firstDealer: PlayerID
        let rules: PreferansRules
        let label: String

        var testDescription: String { label }
    }

    static let configs: [Config] = [
        Config(players: ["north", "east", "south"], firstDealer: "south", rules: .sochi, label: "sochi-3p"),
        Config(
            players: ["north", "east", "south", "west"],
            firstDealer: "west",
            rules: .sochiWithTalonLedAllPass,
            label: "sochi4p-talonLed"
        )
    ]

    static let arguments: [(Config, UInt64)] = configs.flatMap { config in
        (UInt64(1)...UInt64(18)).map { (config, $0) }
    }

    @Test("Seeded legal-action walk preserves invariants and codable round-trip", arguments: arguments)
    func walkPreservesInvariants(config: Config, seed: UInt64) throws {
        var rng = SeededRandomNumberGenerator(seed: seed)
        var engine = try PreferansEngine(
            players: config.players,
            rules: config.rules,
            firstDealer: config.firstDealer
        )

        for step in 0..<180 {
            try assertSnapshotIsValidAndCodable(engine.snapshot, seed: seed, step: step)
            guard let action = try nextLegalAction(engine: engine, rng: &rng) else { break }
            _ = try engine.apply(action)
        }

        try assertSnapshotIsValidAndCodable(engine.snapshot, seed: seed, step: 180)
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
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        try PreferansEngine.validateInvariants(snapshot)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PreferansSnapshot.self, from: data)
        let restored = try PreferansEngine(snapshot: decoded)
        #expect(
            restored.snapshot == snapshot,
            "seed \(seed), step \(step)",
            sourceLocation: sourceLocation
        )
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
