import Foundation

enum AuthProvider: String, Codable, Equatable {
    case apple
    case guest
}

struct OnlineProfile: Identifiable, Codable, Equatable {
    let id: String
    var displayName: String
    var provider: AuthProvider
    var email: String?
    var joinedAt: Date

    init(id: String, displayName: String, provider: AuthProvider, email: String? = nil, joinedAt: Date = .now) {
        self.id = id
        self.displayName = displayName
        self.provider = provider
        self.email = email
        self.joinedAt = joinedAt
    }
}

struct RoomParticipant: Identifiable, Codable, Equatable {
    var id: String { playerID }
    let playerID: String
    var displayName: String
    var seat: Int
    var isHost: Bool
    var joinedAt: Date
    var isReady: Bool

    init(playerID: String, displayName: String, seat: Int, isHost: Bool, joinedAt: Date = .now, isReady: Bool = false) {
        self.playerID = playerID
        self.displayName = displayName
        self.seat = seat
        self.isHost = isHost
        self.joinedAt = joinedAt
        self.isReady = isReady
    }
}

enum OnlineRoomState: String, Codable, Equatable {
    case lobby
    case inHand
    case finished
}

struct OnlineRoom: Identifiable, Codable, Equatable {
    let id: String
    var code: String
    var hostPlayerID: String
    var playerCount: Int
    var ruleSet: PreferansRuleSet
    var participants: [RoomParticipant]
    var state: OnlineRoomState
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        code: String,
        hostPlayerID: String,
        playerCount: Int,
        ruleSet: PreferansRuleSet,
        participants: [RoomParticipant],
        state: OnlineRoomState = .lobby,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.code = code
        self.hostPlayerID = hostPlayerID
        self.playerCount = playerCount
        self.ruleSet = ruleSet
        self.participants = participants
        self.state = state
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isFull: Bool {
        participants.count >= playerCount
    }

    var sortedParticipants: [RoomParticipant] {
        participants.sorted { lhs, rhs in
            if lhs.seat == rhs.seat {
                return lhs.joinedAt < rhs.joinedAt
            }
            return lhs.seat < rhs.seat
        }
    }
}

enum RoomServiceError: LocalizedError {
    case invalidInvite
    case roomNotFound
    case roomFull
    case notHost
    case revisionConflict(serverRevision: Int)

    var errorDescription: String? {
        switch self {
        case .invalidInvite:
            return "The invite link could not be read."
        case .roomNotFound:
            return "This room no longer exists."
        case .roomFull:
            return "This room is already full."
        case .notHost:
            return "Only the host can change this room."
        case let .revisionConflict(serverRevision):
            return "The room changed on another device. Latest revision is \(serverRevision)."
        }
    }
}
