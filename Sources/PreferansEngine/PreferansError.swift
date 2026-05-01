import Foundation

public enum PreferansError: Error, Equatable, LocalizedError, Sendable {
    case invalidPlayer(PlayerID)
    case invalidPlayers(String)
    case invalidDeck(String)
    case invalidContract(String)
    case invalidState(expected: String, actual: String)
    case notPlayersTurn(expected: PlayerID, actual: PlayerID)
    case illegalBid(String)
    case illegalWhist(String)
    case illegalCardPlay(String)
    case cardNotInHand(player: PlayerID, card: Card)
    case duplicateCards([Card])

    public var errorDescription: String? {
        switch self {
        case let .invalidPlayer(player):
            return "Invalid player: \(player)."
        case let .invalidPlayers(message), let .invalidDeck(message), let .invalidContract(message),
             let .illegalBid(message), let .illegalWhist(message), let .illegalCardPlay(message):
            return message
        case let .invalidState(expected, actual):
            return "Invalid state. Expected \(expected), got \(actual)."
        case let .notPlayersTurn(expected, actual):
            return "Expected \(expected), got \(actual)."
        case let .cardNotInHand(player, card):
            return "\(card) is not in \(player)'s hand."
        case let .duplicateCards(cards):
            return "Duplicate cards: \(cards.map(\.description).joined(separator: ", "))."
        }
    }
}
