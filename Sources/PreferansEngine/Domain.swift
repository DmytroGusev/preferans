import Foundation

public struct PlayerID: Hashable, Codable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        precondition(!rawValue.isEmpty, "PlayerID cannot be empty")
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }

    public var description: String { rawValue }
}

public enum Suit: Int, CaseIterable, Codable, Sendable, Comparable, CustomStringConvertible {
    case spades = 0
    case clubs = 1
    case diamonds = 2
    case hearts = 3

    public static func < (lhs: Suit, rhs: Suit) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var symbol: String {
        switch self {
        case .spades: return "♠"
        case .clubs: return "♣"
        case .diamonds: return "♦"
        case .hearts: return "♥"
        }
    }

    public var description: String { symbol }
}

public enum Rank: Int, CaseIterable, Codable, Sendable, Comparable, CustomStringConvertible {
    case seven = 7
    case eight = 8
    case nine = 9
    case ten = 10
    case jack = 11
    case queen = 12
    case king = 13
    case ace = 14

    public static func < (lhs: Rank, rhs: Rank) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var symbol: String {
        switch self {
        case .seven: return "7"
        case .eight: return "8"
        case .nine: return "9"
        case .ten: return "10"
        case .jack: return "J"
        case .queen: return "Q"
        case .king: return "K"
        case .ace: return "A"
        }
    }

    public var description: String { symbol }
}

public struct Card: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let suit: Suit
    public let rank: Rank

    public init(_ suit: Suit, _ rank: Rank) {
        self.suit = suit
        self.rank = rank
    }

    public static func < (lhs: Card, rhs: Card) -> Bool {
        if lhs.suit == rhs.suit {
            return lhs.rank < rhs.rank
        }
        return lhs.suit < rhs.suit
    }

    public var description: String {
        "\(rank.symbol)\(suit.symbol)"
    }
}

public enum Deck {
    public static let standard32: [Card] = Suit.allCases.flatMap { suit in
        Rank.allCases.map { Card(suit, $0) }
    }.sorted()
}

public enum Strain: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    case suit(Suit)
    case noTrump

    public var suit: Suit? {
        if case let .suit(suit) = self { return suit }
        return nil
    }

    public var bidOrder: Int {
        switch self {
        case let .suit(suit): return suit.rawValue
        case .noTrump: return 4
        }
    }

    public static func < (lhs: Strain, rhs: Strain) -> Bool {
        lhs.bidOrder < rhs.bidOrder
    }

    public var description: String {
        switch self {
        case let .suit(suit): return suit.description
        case .noTrump: return "NT"
        }
    }
}

public struct GameContract: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let tricks: Int
    public let strain: Strain

    public init(tricks: Int, strain: Strain) throws {
        guard (6...10).contains(tricks) else {
            throw PreferansError.invalidContract("Game contracts require 6...10 tricks.")
        }
        self.tricks = tricks
        self.strain = strain
    }

    public init(_ tricks: Int, _ strain: Strain) {
        precondition((6...10).contains(tricks), "Game contracts require 6...10 tricks.")
        self.tricks = tricks
        self.strain = strain
    }

    public var bidOrder: Int {
        let base = (tricks - 6) * 5 + strain.bidOrder
        return tricks >= 9 ? base + 1 : base
    }

    public var value: Int {
        (tricks - 5) * 2
    }

    public static func < (lhs: GameContract, rhs: GameContract) -> Bool {
        lhs.bidOrder < rhs.bidOrder
    }

    public var description: String {
        "\(tricks)\(strain.description)"
    }

    public static let allStandard: [GameContract] = (6...10).flatMap { tricks in
        Strain.allStandard.map { GameContract(tricks, $0) }
    }.sorted()
}

public extension Strain {
    static let allStandard: [Strain] = [
        .suit(.spades),
        .suit(.clubs),
        .suit(.diamonds),
        .suit(.hearts),
        .noTrump
    ]
}

public enum ContractBid: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    case game(GameContract)
    case misere
    /// Dedicated 10-trick bid sitting above misère. Only legal when the
    /// match's ``TotusPolicy`` is ``.dedicatedContract``; the actual
    /// trump strain is chosen by the declarer after the discard.
    case totus

    public var order: Int {
        switch self {
        case let .game(contract): return contract.bidOrder
        case .misere: return 15
        case .totus: return 16
        }
    }

    public var value: Int {
        switch self {
        case let .game(contract): return contract.value
        case .misere: return 10
        case .totus: return 10
        }
    }

    public static func < (lhs: ContractBid, rhs: ContractBid) -> Bool {
        lhs.order < rhs.order
    }

    public var description: String {
        switch self {
        case let .game(contract): return contract.description
        case .misere: return "Misere"
        case .totus: return "Totus"
        }
    }

    public static let allStandard: [ContractBid] = (
        GameContract.allStandard.map(ContractBid.game) + [.misere, .totus]
    ).sorted()
}

public enum BidCall: Hashable, Codable, Sendable, CustomStringConvertible {
    case pass
    case bid(ContractBid)

    public var description: String {
        switch self {
        case .pass: return "Pass"
        case let .bid(bid): return bid.description
        }
    }
}

public enum Contract: Hashable, Codable, Sendable, CustomStringConvertible {
    case game(GameContract)
    case misere

    public var value: Int {
        switch self {
        case let .game(contract): return contract.value
        case .misere: return 10
        }
    }

    public var trumpSuit: Suit? {
        switch self {
        case let .game(contract): return contract.strain.suit
        case .misere: return nil
        }
    }

    public var description: String {
        switch self {
        case let .game(contract): return contract.description
        case .misere: return "Misere"
        }
    }
}

public enum WhistCall: Hashable, Codable, Sendable, CustomStringConvertible {
    case pass
    case whist
    case halfWhist

    public var description: String {
        switch self {
        case .pass: return "Pass"
        case .whist: return "Whist"
        case .halfWhist: return "Half-whist"
        }
    }
}

public enum DefenderPlayMode: Hashable, Codable, Sendable {
    case closed
    case open
}

public struct AuctionCall: Hashable, Codable, Sendable {
    public let player: PlayerID
    public let call: BidCall

    public init(player: PlayerID, call: BidCall) {
        self.player = player
        self.call = call
    }
}

public struct WhistCallRecord: Hashable, Codable, Sendable {
    public let player: PlayerID
    public let call: WhistCall

    public init(player: PlayerID, call: WhistCall) {
        self.player = player
        self.call = call
    }
}

public struct CardPlay: Hashable, Codable, Sendable, CustomStringConvertible {
    public let player: PlayerID
    public let card: Card

    public init(player: PlayerID, card: Card) {
        self.player = player
        self.card = card
    }

    public var description: String {
        "\(player): \(card)"
    }
}

public struct Trick: Hashable, Codable, Sendable {
    public let leader: PlayerID
    public let leadSuit: Suit
    public let plays: [CardPlay]
    public let winner: PlayerID

    public init(leader: PlayerID, leadSuit: Suit, plays: [CardPlay], winner: PlayerID) {
        self.leader = leader
        self.leadSuit = leadSuit
        self.plays = plays
        self.winner = winner
    }
}
