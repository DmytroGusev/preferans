import Foundation

/// Replays a ``MatchScript`` through a freshly constructed ``PreferansEngine``
/// and returns the resulting ``MatchSummary``. Faults loudly via
/// ``MatchScriptError`` when the script disagrees with the engine — most
/// commonly a missing step or a wrong action count.
public struct EngineMatchDriver {
    public let script: MatchScript

    public init(script: MatchScript) {
        self.script = script
    }

    /// Runs the script to completion. The match must reach
    /// ``DealState/gameOver`` while consuming exactly the listed deals;
    /// over- or under-supplying deals throws.
    @discardableResult
    public func run() throws -> MatchSummary {
        let engine = try runReturningEngine()
        guard case let .gameOver(summary) = engine.state else {
            throw MatchScriptError.matchDidNotReachGameOver(finalState: engine.state.description)
        }
        return summary
    }

    /// Runs the script and returns the engine after the run, preserving the
    /// final state for tests that need to inspect e.g. `nextDealer` or the
    /// score sheet beyond what ``MatchSummary`` exposes.
    public func runReturningEngine() throws -> PreferansEngine {
        try MatchScriptStepper(script: script).run()
    }
}

/// Shared replay engine for ``MatchScript``. The plain engine driver uses it
/// directly; UI tests attach hooks that tap the SwiftUI surface before each
/// mirrored engine action.
public struct MatchScriptStepper {
    public let script: MatchScript

    public init(script: MatchScript) {
        self.script = script
    }

    public func makeEngine() throws -> PreferansEngine {
        try PreferansEngine(
            players: script.players,
            rules: script.rules,
            match: script.match,
            firstDealer: script.firstDealer
        )
    }

    @discardableResult
    public func run(hooks: Hooks = Hooks()) throws -> PreferansEngine {
        var engine = try makeEngine()
        for (index, deal) in script.deals.enumerated() {
            if case .gameOver = engine.state {
                throw MatchScriptError.gameOverBeforeDealConsumed(dealIndex: index)
            }
            try drive(deal: deal, dealIndex: index, engine: &engine, hooks: hooks)
        }
        return engine
    }

    public struct Hooks {
        public var beforeDeal: (Int, DealScript, PreferansEngine) throws -> Void
        public var afterStartDeal: (Int, DealScript, PreferansEngine) throws -> Void
        public var beforeAction: (Int, Step, PreferansAction, PreferansEngine) throws -> Void

        public init(
            beforeDeal: @escaping (Int, DealScript, PreferansEngine) throws -> Void = { _, _, _ in },
            afterStartDeal: @escaping (Int, DealScript, PreferansEngine) throws -> Void = { _, _, _ in },
            beforeAction: @escaping (Int, Step, PreferansAction, PreferansEngine) throws -> Void = { _, _, _, _ in }
        ) {
            self.beforeDeal = beforeDeal
            self.afterStartDeal = afterStartDeal
            self.beforeAction = beforeAction
        }
    }

    public enum Step: Sendable, Equatable {
        case auction
        case discard
        case contractDeclaration
        case whist
        case defenderMode
        case play
    }

    private func drive(
        deal: DealScript,
        dealIndex: Int,
        engine: inout PreferansEngine,
        hooks: Hooks
    ) throws {
        try hooks.beforeDeal(dealIndex, deal, engine)
        let dealer = engine.nextDealer
        let activePlayers = engine.activePlayers(forDealer: dealer)
        let deck = deal.recipe.deck(for: activePlayers)
        try engine.startDeal(deck: deck)
        try hooks.afterStartDeal(dealIndex, deal, engine)

        try driveAuction(deal.auction, dealIndex: dealIndex, engine: &engine, hooks: hooks)
        try driveDiscard(deal.discardChoice, dealIndex: dealIndex, engine: &engine, hooks: hooks)
        try driveContractDeclaration(deal.contractDeclaration, dealIndex: dealIndex, engine: &engine, hooks: hooks)
        try driveWhists(deal.whists, dealIndex: dealIndex, engine: &engine, hooks: hooks)
        try driveDefenderMode(deal.defenderMode, dealIndex: dealIndex, engine: &engine, hooks: hooks)
        try drivePlay(deal.cardPlay, dealIndex: dealIndex, engine: &engine, hooks: hooks)
    }

    private func driveAuction(
        _ calls: [BidCall],
        dealIndex: Int,
        engine: inout PreferansEngine,
        hooks: Hooks
    ) throws {
        for call in calls {
            guard case let .bidding(state) = engine.state else {
                // Auction may end before all scripted calls are consumed —
                // e.g., second-bid pass triggers an auction-won transition.
                // Surface the leftover as an error so scripts stay tight.
                throw MatchScriptError.unexpectedAuctionExit(dealIndex: dealIndex, state: engine.state.description)
            }
            try apply(.bid(player: state.currentPlayer, call: call), step: .auction, dealIndex: dealIndex, engine: &engine, hooks: hooks)
        }
    }

    private func driveDiscard(
        _ choice: DiscardChoice,
        dealIndex: Int,
        engine: inout PreferansEngine,
        hooks: Hooks
    ) throws {
        guard case let .awaitingDiscard(exchange) = engine.state else { return }
        let cards: [Card]
        switch choice {
        case .talon:
            cards = exchange.talon
        case let .specific(specified):
            cards = specified
        case .none:
            throw MatchScriptError.missingDiscardChoice(dealIndex: dealIndex)
        }
        try apply(.discard(player: exchange.declarer, cards: cards), step: .discard, dealIndex: dealIndex, engine: &engine, hooks: hooks)
    }

    private func driveContractDeclaration(
        _ contract: GameContract?,
        dealIndex: Int,
        engine: inout PreferansEngine,
        hooks: Hooks
    ) throws {
        guard case let .awaitingContract(declaration) = engine.state else { return }
        guard let contract else {
            throw MatchScriptError.missingContractDeclaration(dealIndex: dealIndex)
        }
        try apply(.declareContract(player: declaration.declarer, contract: contract), step: .contractDeclaration, dealIndex: dealIndex, engine: &engine, hooks: hooks)
    }

    private func driveWhists(
        _ calls: [WhistCall],
        dealIndex: Int,
        engine: inout PreferansEngine,
        hooks: Hooks
    ) throws {
        guard !calls.isEmpty else { return }
        for call in calls {
            guard case let .awaitingWhist(state) = engine.state else { return }
            try apply(.whist(player: state.currentPlayer, call: call), step: .whist, dealIndex: dealIndex, engine: &engine, hooks: hooks)
        }
    }

    private func driveDefenderMode(
        _ mode: DefenderPlayMode?,
        dealIndex: Int,
        engine: inout PreferansEngine,
        hooks: Hooks
    ) throws {
        guard case let .awaitingDefenderMode(state) = engine.state else { return }
        guard let mode else {
            throw MatchScriptError.missingDefenderMode(dealIndex: dealIndex)
        }
        try apply(.chooseDefenderMode(player: state.whister, mode: mode), step: .defenderMode, dealIndex: dealIndex, engine: &engine, hooks: hooks)
    }

    private func drivePlay(
        _ strategy: CardPlayStrategy,
        dealIndex: Int,
        engine: inout PreferansEngine,
        hooks: Hooks
    ) throws {
        switch strategy {
        case .none:
            return
        case let .exact(cards):
            for card in cards {
                guard case let .playing(state) = engine.state else { return }
                try apply(.playCard(player: state.currentPlayer, card: card), step: .play, dealIndex: dealIndex, engine: &engine, hooks: hooks)
            }
        case let .greedyForDeclarer(declarer):
            // Compare by rank only — the engine's Card.Comparable sorts
            // suit-first, which would have declarer "leading" their lowest
            // heart over their ace of clubs. Trick play cares about rank, not
            // bid-order suit precedence.
            try playLoop(engine: &engine, dealIndex: dealIndex, hooks: hooks) { actor, legal in
                actor == declarer
                    ? legal.max(by: { $0.rank.rawValue < $1.rank.rawValue })
                    : legal.min(by: { $0.rank.rawValue < $1.rank.rawValue })
            }
        case .lowestLegal:
            try playLoop(engine: &engine, dealIndex: dealIndex, hooks: hooks) { _, legal in
                legal.min(by: { $0.rank.rawValue < $1.rank.rawValue })
            }
        }
    }

    private func playLoop(
        engine: inout PreferansEngine,
        dealIndex: Int,
        hooks: Hooks,
        choose: (PlayerID, [Card]) -> Card?
    ) throws {
        var safety = 64
        while case let .playing(state) = engine.state, safety > 0 {
            safety -= 1
            let actor = state.currentPlayer
            let legal = engine.legalCards(for: actor)
            guard let card = choose(actor, legal) else {
                throw MatchScriptError.noLegalCard(dealIndex: dealIndex, player: actor)
            }
            try apply(.playCard(player: actor, card: card), step: .play, dealIndex: dealIndex, engine: &engine, hooks: hooks)
        }
        if safety == 0 {
            throw MatchScriptError.playLoopRunaway(dealIndex: dealIndex)
        }
    }

    private func apply(
        _ action: PreferansAction,
        step: Step,
        dealIndex: Int,
        engine: inout PreferansEngine,
        hooks: Hooks
    ) throws {
        try hooks.beforeAction(dealIndex, step, action, engine)
        _ = try engine.apply(action)
    }
}

public enum MatchScriptError: Error, Equatable, CustomStringConvertible {
    case gameOverBeforeDealConsumed(dealIndex: Int)
    case matchDidNotReachGameOver(finalState: String)
    case unexpectedAuctionExit(dealIndex: Int, state: String)
    case missingDiscardChoice(dealIndex: Int)
    case missingContractDeclaration(dealIndex: Int)
    case missingDefenderMode(dealIndex: Int)
    case noLegalCard(dealIndex: Int, player: PlayerID)
    case playLoopRunaway(dealIndex: Int)

    public var description: String {
        switch self {
        case let .gameOverBeforeDealConsumed(i):
            return "Match ended before deal #\(i) was consumed — script over-supplies deals."
        case let .matchDidNotReachGameOver(state):
            return "Script ran to completion but engine state is \(state), not gameOver — script under-supplies deals."
        case let .unexpectedAuctionExit(i, state):
            return "Auction exited prematurely on deal #\(i): engine moved to \(state) before the scripted bids were consumed."
        case let .missingDiscardChoice(i):
            return "Deal #\(i) reached awaitingDiscard but the script provided DiscardChoice.none."
        case let .missingContractDeclaration(i):
            return "Deal #\(i) reached awaitingContract but the script's contractDeclaration is nil."
        case let .missingDefenderMode(i):
            return "Deal #\(i) reached awaitingDefenderMode but the script's defenderMode is nil."
        case let .noLegalCard(i, player):
            return "No legal card available for \(player) on deal #\(i)."
        case let .playLoopRunaway(i):
            return "Card play on deal #\(i) did not terminate within 64 trick steps."
        }
    }
}
