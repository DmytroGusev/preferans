import Foundation
import PreferansEngine

public enum GameWireMessage: Codable, Sendable, Equatable {
    case hello(HelloEnvelope)
    case seatAssignment(SeatAssignmentEnvelope)
    case clientAction(ClientActionEnvelope)
    case projection(ProjectionEnvelope)
    case hostError(HostErrorEnvelope)
    case resyncRequest(ResyncRequestEnvelope)
    case ping(PingEnvelope)
}

public struct HelloEnvelope: Codable, Sendable, Equatable {
    public var schemaVersion: Int = AppIdentifiers.gameWireSchemaVersion
    public var tableID: UUID?
    public var player: PlayerIdentity
    public var lastSeenSequence: Int

    public init(tableID: UUID?, player: PlayerIdentity, lastSeenSequence: Int) {
        self.tableID = tableID
        self.player = player
        self.lastSeenSequence = lastSeenSequence
    }
}

public struct SeatAssignmentEnvelope: Codable, Sendable, Equatable {
    public var schemaVersion: Int = AppIdentifiers.gameWireSchemaVersion
    public var tableID: UUID
    public var hostPlayerID: PlayerID
    public var seats: [PlayerIdentity]
    public var rules: PreferansRules

    public init(tableID: UUID, hostPlayerID: PlayerID, seats: [PlayerIdentity], rules: PreferansRules) {
        self.tableID = tableID
        self.hostPlayerID = hostPlayerID
        self.seats = seats
        self.rules = rules
    }
}

public struct ClientActionEnvelope: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID { clientNonce }
    public var schemaVersion: Int = AppIdentifiers.gameWireSchemaVersion
    public var tableID: UUID
    public var actor: PlayerID
    public var action: PreferansAction
    public var clientNonce: UUID
    public var baseHostSequence: Int
    public var sentAt: Date

    public init(
        tableID: UUID,
        actor: PlayerID,
        action: PreferansAction,
        clientNonce: UUID = UUID(),
        baseHostSequence: Int,
        sentAt: Date = Date()
    ) {
        self.tableID = tableID
        self.actor = actor
        self.action = action
        self.clientNonce = clientNonce
        self.baseHostSequence = baseHostSequence
        self.sentAt = sentAt
    }
}

public struct ProjectionEnvelope: Codable, Sendable, Equatable {
    public var schemaVersion: Int = AppIdentifiers.gameWireSchemaVersion
    public var tableID: UUID
    public var sequence: Int
    public var viewer: PlayerID
    public var projection: PlayerGameProjection
    public var eventSummaries: [String]

    public init(tableID: UUID, sequence: Int, viewer: PlayerID, projection: PlayerGameProjection, eventSummaries: [String]) {
        self.tableID = tableID
        self.sequence = sequence
        self.viewer = viewer
        self.projection = projection
        self.eventSummaries = eventSummaries
    }
}

public struct HostErrorEnvelope: Codable, Sendable, Equatable {
    public var schemaVersion: Int = AppIdentifiers.gameWireSchemaVersion
    public var tableID: UUID
    public var sequence: Int
    public var recipient: PlayerID?
    public var clientNonce: UUID?
    public var message: String

    public init(tableID: UUID, sequence: Int, recipient: PlayerID?, clientNonce: UUID?, message: String) {
        self.tableID = tableID
        self.sequence = sequence
        self.recipient = recipient
        self.clientNonce = clientNonce
        self.message = message
    }
}

public struct ResyncRequestEnvelope: Codable, Sendable, Equatable {
    public var schemaVersion: Int = AppIdentifiers.gameWireSchemaVersion
    public var tableID: UUID
    public var requester: PlayerID
    public var lastSeenSequence: Int

    public init(tableID: UUID, requester: PlayerID, lastSeenSequence: Int) {
        self.tableID = tableID
        self.requester = requester
        self.lastSeenSequence = lastSeenSequence
    }
}

public struct PingEnvelope: Codable, Sendable, Equatable {
    public var schemaVersion: Int = AppIdentifiers.gameWireSchemaVersion
    public var tableID: UUID?
    public var sentAt: Date

    public init(tableID: UUID?, sentAt: Date = Date()) {
        self.tableID = tableID
        self.sentAt = sentAt
    }
}
