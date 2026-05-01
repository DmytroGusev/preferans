import Foundation
import PreferansEngine

/// Codable mirror for PreferansAction. This avoids requiring the engine enum itself to be Codable.
public enum WirePreferansAction: Codable, Sendable, Equatable {
    case startDeal(dealer: PlayerID?, deck: [Card]?)
    case bid(player: PlayerID, call: BidCall)
    case discard(player: PlayerID, cards: [Card])
    case declareContract(player: PlayerID, contract: GameContract)
    case whist(player: PlayerID, call: WhistCall)
    case chooseDefenderMode(player: PlayerID, mode: DefenderPlayMode)
    case playCard(player: PlayerID, card: Card)

    public init(_ action: PreferansAction) {
        switch action {
        case let .startDeal(dealer, deck):
            self = .startDeal(dealer: dealer, deck: deck)
        case let .bid(player, call):
            self = .bid(player: player, call: call)
        case let .discard(player, cards):
            self = .discard(player: player, cards: cards)
        case let .declareContract(player, contract):
            self = .declareContract(player: player, contract: contract)
        case let .whist(player, call):
            self = .whist(player: player, call: call)
        case let .chooseDefenderMode(player, mode):
            self = .chooseDefenderMode(player: player, mode: mode)
        case let .playCard(player, card):
            self = .playCard(player: player, card: card)
        }
    }

    public var action: PreferansAction {
        switch self {
        case let .startDeal(dealer, deck):
            return .startDeal(dealer: dealer, deck: deck)
        case let .bid(player, call):
            return .bid(player: player, call: call)
        case let .discard(player, cards):
            return .discard(player: player, cards: cards)
        case let .declareContract(player, contract):
            return .declareContract(player: player, contract: contract)
        case let .whist(player, call):
            return .whist(player: player, call: call)
        case let .chooseDefenderMode(player, mode):
            return .chooseDefenderMode(player: player, mode: mode)
        case let .playCard(player, card):
            return .playCard(player: player, card: card)
        }
    }

    public var actor: PlayerID? {
        switch self {
        case .startDeal:
            return nil
        case let .bid(player, _),
             let .discard(player, _),
             let .declareContract(player, _),
             let .whist(player, _),
             let .chooseDefenderMode(player, _),
             let .playCard(player, _):
            return player
        }
    }
}
