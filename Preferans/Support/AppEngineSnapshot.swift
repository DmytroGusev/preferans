import Foundation
import PreferansEngine

/// A codable diagnostic/read-cache payload that can be produced by the app
/// without modifying the engine. CloudKit stores it as a convenience
/// projection; the authoritative history is the validated action/event log,
/// which can rebuild the live engine through `GameLogReplayer`.
public struct AppEngineSnapshot: Codable, Sendable, Equatable {
    public var players: [PlayerID]
    public var rules: PreferansRules
    public var state: DealState
    public var score: ScoreSheet
    public var nextDealer: PlayerID

    public init(engine: PreferansEngine) {
        self.players = engine.players
        self.rules = engine.rules
        self.state = engine.state
        self.score = engine.score
        self.nextDealer = engine.nextDealer
    }
}
