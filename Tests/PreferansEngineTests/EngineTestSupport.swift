import Foundation
@testable import PreferansApp
@testable import PreferansEngine

struct EngineTestError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

enum EnginePlayPolicy {
    case lowestLegal
    case highestLegal
    case declarerHighestDefendersLowest(declarer: PlayerID)

    func choose(engine: PreferansEngine, actor: PlayerID) -> Card? {
        let legal = engine.legalCards(for: actor)
        switch self {
        case .lowestLegal:
            return legal.min()
        case .highestLegal:
            return legal.max()
        case let .declarerHighestDefendersLowest(declarer):
            return actor == declarer ? legal.max() : legal.min()
        }
    }
}

enum EngineTestDriver {
    static func activeRotation(players: [PlayerID], firstDealer: PlayerID) throws -> [PlayerID] {
        let engine = try PreferansEngine(players: players, firstDealer: firstDealer)
        return engine.activePlayers(forDealer: firstDealer)
    }

    static func driveAuctionWinning(engine: inout PreferansEngine, declarer: PlayerID, bid: ContractBid) throws {
        guard case let .bidding(state) = engine.state else {
            throw EngineTestError("Expected bidding state at start of auction.")
        }
        for seat in state.activePlayers {
            let call: BidCall = seat == declarer ? .bid(bid) : .pass
            _ = try engine.apply(.bid(player: seat, call: call))
        }
    }

    static func passOutAuction(engine: inout PreferansEngine) throws {
        guard case let .bidding(state) = engine.state else {
            throw EngineTestError("Expected bidding state at start of pass-out auction.")
        }
        for seat in state.activePlayers {
            _ = try engine.apply(.bid(player: seat, call: .pass))
        }
    }

    static func discardTalon(engine: inout PreferansEngine, declarer: PlayerID) throws {
        guard case let .awaitingDiscard(exchange) = engine.state else {
            throw EngineTestError("Expected awaitingDiscard; got \(engine.state.description).")
        }
        _ = try engine.apply(.discard(player: declarer, cards: exchange.talon))
    }

    static func declareContract(engine: inout PreferansEngine, declarer: PlayerID, contract: GameContract) throws {
        _ = try engine.apply(.declareContract(player: declarer, contract: contract))
    }

    static func forceWhist(engine: inout PreferansEngine) throws {
        guard case let .awaitingWhist(state) = engine.state else {
            throw EngineTestError("Expected awaitingWhist; got \(engine.state.description).")
        }
        for defender in state.defenders {
            _ = try engine.apply(.whist(player: defender, call: .whist))
        }
    }

    @discardableResult
    static func playOut(engine: inout PreferansEngine, policy: EnginePlayPolicy, stepLimit: Int = 64) throws -> Int {
        var steps = 0
        while case let .playing(state) = engine.state, steps < stepLimit {
            let actor = state.currentPlayer
            guard let card = policy.choose(engine: engine, actor: actor) else {
                throw EngineTestError("No legal card for \(actor) at trick \(state.completedTricks.count).")
            }
            _ = try engine.apply(.playCard(player: actor, card: card))
            steps += 1
        }
        if steps >= stepLimit, case .playing = engine.state {
            throw EngineTestError("Playing state did not terminate within \(stepLimit) steps.")
        }
        return steps
    }
}

@MainActor
enum GameViewModelTestDriver {
    @discardableResult
    static func playOutCurrentDeal(
        _ model: GameViewModel,
        policy: EnginePlayPolicy,
        stepLimit: Int = 64
    ) -> Bool {
        var steps = 0
        while case let .playing(state) = model.engine.state, steps < stepLimit {
            let actor = state.currentPlayer
            guard let card = policy.choose(engine: model.engine, actor: actor) else {
                return false
            }
            model.send(.playCard(player: actor, card: card))
            if model.lastError != nil { return false }
            steps += 1
        }
        if case .playing = model.engine.state, steps >= stepLimit {
            return false
        }
        return true
    }
}

struct BotDriveResult: Sendable {
    var steps: Int
    var stalled: Bool
    var illegalActionAttempts: Int
}

enum BotTestDriver {
    @discardableResult
    static func drive(
        engine: inout PreferansEngine,
        strategy: PlayerStrategy,
        stepLimit: Int = 500
    ) async throws -> BotDriveResult {
        var steps = 0
        while steps < stepLimit {
            guard let actor = engine.state.currentActor else {
                return BotDriveResult(steps: steps, stalled: false, illegalActionAttempts: 0)
            }
            guard let action = await strategy.decide(snapshot: engine.snapshot, viewer: actor) else {
                return BotDriveResult(steps: steps, stalled: true, illegalActionAttempts: 0)
            }
            do {
                _ = try engine.apply(action)
            } catch {
                return BotDriveResult(steps: steps, stalled: true, illegalActionAttempts: 1)
            }
            steps += 1
        }
        return BotDriveResult(steps: steps, stalled: true, illegalActionAttempts: 0)
    }
}
