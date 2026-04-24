import Foundation

enum Suit: String, CaseIterable, Codable, Identifiable {
    case spades
    case clubs
    case diamonds
    case hearts

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .clubs: "♣"
        case .spades: "♠"
        case .diamonds: "♦"
        case .hearts: "♥"
        }
    }

    var rank: Int {
        switch self {
        case .spades: 0
        case .clubs: 1
        case .diamonds: 2
        case .hearts: 3
        }
    }
}

enum Rank: Int, CaseIterable, Codable {
    case seven = 7
    case eight = 8
    case nine = 9
    case ten = 10
    case jack = 11
    case queen = 12
    case king = 13
    case ace = 14

    var label: String {
        switch self {
        case .seven: "7"
        case .eight: "8"
        case .nine: "9"
        case .ten: "10"
        case .jack: "J"
        case .queen: "Q"
        case .king: "K"
        case .ace: "A"
        }
    }
}

struct Card: Identifiable, Codable, Hashable {
    let suit: Suit
    let rank: Rank

    var id: String { "\(rank.rawValue)-\(suit.rawValue)" }
    var label: String { "\(rank.label)\(suit.symbol)" }
}

struct Player: Identifiable, Codable {
    let id: UUID
    var name: String
    var seat: Int
    var hand: [Card]
    var tricksWon: Int
    var score: Int
    var pool: Int
    var mountain: Int
    var isSittingOut: Bool

    init(id: UUID = UUID(), name: String, seat: Int, hand: [Card] = [], tricksWon: Int = 0, score: Int = 0, pool: Int = 0, mountain: Int = 0, isSittingOut: Bool = false) {
        self.id = id
        self.name = name
        self.seat = seat
        self.hand = hand
        self.tricksWon = tricksWon
        self.score = score
        self.pool = pool
        self.mountain = mountain
        self.isSittingOut = isSittingOut
    }
}

struct Bid: Identifiable, Equatable {
    let id = UUID()
    let playerID: UUID
    let contract: Contract

    var strength: Int {
        contract.strength
    }

    var title: String {
        contract.title
    }
}

enum Contract: Equatable, Codable {
    case suited(tricks: Int, trump: Suit)
    case noTrump(tricks: Int)
    case misere
    case raspasy

    var strength: Int {
        guard let index = Contract.orderedContracts.firstIndex(of: self) else { return -1 }
        return index
    }

    var title: String {
        switch self {
        case let .suited(tricks, trump):
            return "\(tricks) \(trump.symbol)"
        case let .noTrump(tricks):
            return "\(tricks) NT"
        case .misere:
            return "Misere"
        case .raspasy:
            return "Raspasy"
        }
    }

    var targetTricks: Int? {
        switch self {
        case let .suited(tricks, _), let .noTrump(tricks):
            return tricks
        case .misere:
            return 0
        case .raspasy:
            return nil
        }
    }

    var trump: Suit? {
        switch self {
        case let .suited(_, trump):
            return trump
        case .noTrump, .misere, .raspasy:
            return nil
        }
    }

    var gameValue: Int {
        switch self {
        case let .suited(tricks, _), let .noTrump(tricks):
            return max(0, (tricks - 5) * 2)
        case .misere:
            return 10
        case .raspasy:
            return 0
        }
    }

    var defenderQuota: Int? {
        switch self {
        case .suited(6, _), .noTrump(6):
            return 4
        case .suited(7, _), .noTrump(7):
            return 2
        case .suited, .noTrump:
            return 1
        case .misere, .raspasy:
            return nil
        }
    }

    var isTrickGame: Bool {
        switch self {
        case .suited, .noTrump:
            return true
        case .misere, .raspasy:
            return false
        }
    }

    static var orderedContracts: [Contract] {
        var contracts: [Contract] = []

        for tricks in [6, 7] {
            for suit in Suit.allCases {
                contracts.append(.suited(tricks: tricks, trump: suit))
            }
            contracts.append(.noTrump(tricks: tricks))
        }

        contracts.append(.misere)

        for tricks in [8, 9, 10] {
            for suit in Suit.allCases {
                contracts.append(.suited(tricks: tricks, trump: suit))
            }
            contracts.append(.noTrump(tricks: tricks))
        }

        return contracts
    }
}

struct TrickPlay: Identifiable, Equatable {
    let id = UUID()
    let playerID: UUID
    let card: Card
}

struct RoomInvite: Identifiable {
    let id = UUID()
    let code: String
    let url: URL
}

enum GameScreen: Codable, Equatable {
    case lobby
    case table
}

enum Phase: Codable, Equatable {
    case setup
    case bidding
    case takingTalon
    case discarding
    case declaringContract
    case whisting
    case playing
    case handFinished
}

enum PreferansRuleSet: String, CaseIterable, Codable, Identifiable {
    case sochi
    case leningrad
    case rostov

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sochi: return "Sochi"
        case .leningrad: return "Leningrad"
        case .rostov: return "Rostov"
        }
    }

    var subtitle: String {
        switch self {
        case .sochi:
            return "Classic pool, mountain and whists."
        case .leningrad:
            return "Mountain and whists are doubled."
        case .rostov:
            return "Whists are softer, mountain converts into whists."
        }
    }

    var targetPool: Int { 10 }

    func recordedWhists(_ value: Int) -> Int {
        switch self {
        case .sochi: return value
        case .leningrad: return value * 2
        case .rostov: return max(1, value / 2)
        }
    }

    func recordedMountain(_ value: Int) -> Int {
        switch self {
        case .sochi: return value
        case .leningrad: return value * 2
        case .rostov: return 0
        }
    }
}

enum WhistDecision: String, Codable, CaseIterable {
    case undecided
    case pass
    case halfWhist
    case whist

    var title: String {
        switch self {
        case .undecided: return "Undecided"
        case .pass: return "Pass"
        case .halfWhist: return "Half-Whist"
        case .whist: return "Whist"
        }
    }
}

enum ClaimResponse: String, Codable, CaseIterable {
    case pending
    case accepted
    case rejected

    var title: String {
        switch self {
        case .pending: return "Pending"
        case .accepted: return "Accepted"
        case .rejected: return "Rejected"
        }
    }
}

struct TrickClaimProposal: Identifiable, Equatable {
    let id = UUID()
    let proposerID: UUID
    var targetPlayerID: UUID
    var claimedTotalTricks: Int
    var responses: [UUID: ClaimResponse]

    func response(for playerID: UUID) -> ClaimResponse {
        responses[playerID] ?? .pending
    }
}
