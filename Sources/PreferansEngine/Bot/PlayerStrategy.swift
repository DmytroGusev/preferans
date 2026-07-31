import Foundation

/// A pluggable decision-maker for a single seat. The view model invokes the
/// strategy whenever the active actor is a bot seat and applies the returned
/// action through the engine. Strategies must be pure functions of the
/// snapshot — the same input may be replayed during testing.
public protocol PlayerStrategy: Sendable {
    /// Decides the next action for `viewer`. Returns `nil` only when the
    /// strategy refuses to act (e.g., the snapshot is not actually awaiting
    /// `viewer`); in normal use this never returns `nil` for a seat the
    /// caller has confirmed is the active actor.
    func decide(
        snapshot: PreferansSnapshot,
        viewer: PlayerID
    ) async -> PreferansAction?

    /// Returns the same action together with a short, public-safe account of
    /// the bot's intent. Custom strategies can keep implementing only
    /// ``decide(snapshot:viewer:)``; the default adapter preserves source
    /// compatibility and simply omits the explanation.
    func decision(
        snapshot: PreferansSnapshot,
        viewer: PlayerID
    ) async -> StrategyDecision?
}

/// One strategy result. The action remains the sole engine input; the optional
/// explanation is presentation metadata and is never trusted or replayed as
/// game state.
public struct StrategyDecision: Equatable, Sendable {
    public var action: PreferansAction
    public var explanation: BotDecisionExplanation?

    public init(
        action: PreferansAction,
        explanation: BotDecisionExplanation? = nil
    ) {
        self.action = action
        self.explanation = explanation
    }
}

/// Generic, non-card-revealing reasons a bot can give after acting. These are
/// deliberately categorical: an explanation may reveal the bot's style, but
/// never its cards, sampled hidden hands, or exact evaluator score.
public enum BotDecisionRationale: String, Codable, CaseIterable, Hashable, Sendable {
    case auctionPass
    case gameBid
    case misereBid
    case totusBid
    case contractFit
    case contractConcession
    case discardForContract
    case discardForMisere
    case fullWhist
    case halfWhist
    case defensivePass
    case openDefense
    case closedDefense
    case forcedSettlement
    case contestSettlement

    public var category: BotDecisionCategory {
        switch self {
        case .auctionPass, .gameBid, .misereBid, .totusBid:
            return .auction
        case .contractFit, .contractConcession:
            return .contract
        case .discardForContract, .discardForMisere:
            return .discard
        case .fullWhist, .halfWhist, .defensivePass:
            return .whist
        case .openDefense, .closedDefense:
            return .defenderMode
        case .forcedSettlement, .contestSettlement:
            return .settlement
        }
    }
}

public enum BotDecisionCategory: String, Codable, Hashable, Sendable {
    case auction
    case contract
    case discard
    case whist
    case defenderMode
    case settlement
}

/// A lightweight player-facing note attached to a bot move. It contains only
/// stable profile metadata and a categorical rationale, so retaining it in an
/// activity window cannot leak hidden cards.
public struct BotDecisionExplanation: Equatable, Hashable, Sendable {
    public var actor: PlayerID
    public var profile: BotProfile
    public var rationale: BotDecisionRationale

    public init(
        actor: PlayerID,
        profile: BotProfile,
        rationale: BotDecisionRationale
    ) {
        self.actor = actor
        self.profile = profile
        self.rationale = rationale
    }
}

public extension PlayerStrategy {
    func decision(
        snapshot: PreferansSnapshot,
        viewer: PlayerID
    ) async -> StrategyDecision? {
        guard let action = await decide(snapshot: snapshot, viewer: viewer) else {
            return nil
        }
        return StrategyDecision(action: action)
    }
}
