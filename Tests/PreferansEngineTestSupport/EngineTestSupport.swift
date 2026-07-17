import Foundation
import PreferansEngine

struct EngineTestError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

final class CountingDealSource: DealSource, @unchecked Sendable {
    private let decks: [[Card]]
    private var index = 0
    private var storedRequestCount = 0
    private let lock = NSLock()

    var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedRequestCount
    }

    init(decks: [[Card]]) {
        precondition(!decks.isEmpty, "CountingDealSource requires at least one deck")
        self.decks = decks
    }

    func nextDeck() -> [Card] {
        lock.lock()
        defer { lock.unlock() }
        defer {
            index += 1
            storedRequestCount += 1
        }
        return decks[index % decks.count]
    }
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

enum BotDriveStopReason: Sendable, Equatable {
    case phaseCompleted
    case strategyReturnedNoAction(actor: PlayerID, decider: PlayerID)
    case engineRejectedAction(
        actor: PlayerID,
        decider: PlayerID,
        action: PreferansAction,
        error: String
    )
    case stepLimitReached(limit: Int, actor: PlayerID, decider: PlayerID)
}

struct BotDriveResult: Sendable, Equatable {
    let steps: Int
    let stopReason: BotDriveStopReason

    /// Compatibility view for callers that only need success/failure.
    var stalled: Bool {
        stopReason != .phaseCompleted
    }

    /// Compatibility view retained for the simulation report.
    var illegalActionAttempts: Int {
        if case .engineRejectedAction = stopReason { return 1 }
        return 0
    }
}

enum BotTestDriver {
    @discardableResult
    static func drive(
        engine: inout PreferansEngine,
        strategy: PlayerStrategy,
        stepLimit: Int = 96
    ) async throws -> BotDriveResult {
        var steps = 0
        while steps < stepLimit {
            guard let actor = engine.state.currentActor else {
                return BotDriveResult(steps: steps, stopReason: .phaseCompleted)
            }
            // The seat authorized to decide may differ from the seat
            // whose turn it physically is — in open single-whist greedy
            // play the lone whister pulls the passer's dummy hand, so the
            // strategy is queried for the whister's perspective.
            let decider = engine.controllingActor(of: actor)
            guard let action = await strategy.decide(snapshot: engine.snapshot, viewer: decider) else {
                return BotDriveResult(
                    steps: steps,
                    stopReason: .strategyReturnedNoAction(actor: actor, decider: decider)
                )
            }
            do {
                _ = try engine.apply(action)
            } catch {
                let description = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                return BotDriveResult(
                    steps: steps,
                    stopReason: .engineRejectedAction(
                        actor: actor,
                        decider: decider,
                        action: action,
                        error: description
                    )
                )
            }
            steps += 1
        }

        // The final permitted action may itself complete the deal. Re-read
        // engine state before diagnosing the loop bound as a stall.
        guard let actor = engine.state.currentActor else {
            return BotDriveResult(steps: steps, stopReason: .phaseCompleted)
        }
        let decider = engine.controllingActor(of: actor)
        return BotDriveResult(
            steps: steps,
            stopReason: .stepLimitReached(limit: stepLimit, actor: actor, decider: decider)
        )
    }
}
