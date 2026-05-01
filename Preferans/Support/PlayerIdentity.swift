import Foundation
import PreferansEngine

public struct PlayerIdentity: Codable, Sendable, Hashable, Identifiable {
    public var id: PlayerID { playerID }
    public var playerID: PlayerID
    public var gamePlayerID: String
    public var displayName: String

    public init(playerID: PlayerID, gamePlayerID: String, displayName: String) {
        self.playerID = playerID
        self.gamePlayerID = gamePlayerID
        self.displayName = displayName
    }
}
