import Foundation
import PreferansEngine

/// A codable diagnostic/persistence payload that can be produced by the app without modifying the engine.
/// It is useful for CloudKit archival. Rehydrating a live engine from this payload still requires either
/// the optional engine snapshot initializer or a replay of the validated action log.
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
