import Foundation
import PreferansEngine

/// Pure acceptance rules for room frames before they mutate coordinator state.
/// Transport recipient routing is not an authority boundary: every host-owned
/// frame must still match the elected host, table, viewer, and sequence.
enum RoomInboundMessagePolicy {
    struct FrameID: Equatable {
        var tableID: UUID
        var sequence: Int
    }

    enum ProjectionDecision: Equatable {
        case reject
        /// Same table and sequence: refresh replaceable state only. Structured
        /// events must not be appended a second time.
        case refresh
        case advance
    }

    static func acceptsHello(_ hello: HelloEnvelope) -> Bool {
        hello.schemaVersion == AppIdentifiers.gameWireSchemaVersion
    }

    static func acceptsClientAction(_ envelope: ClientActionEnvelope) -> Bool {
        envelope.schemaVersion == AppIdentifiers.gameWireSchemaVersion
    }

    static func isFromElectedHost(
        _ sender: OnlinePeer,
        localIsHost: Bool,
        electedHost: PlayerID?
    ) -> Bool {
        !localIsHost && sender.playerID == electedHost
    }

    static func acceptsSeatAssignment(
        _ assignment: SeatAssignmentEnvelope,
        sender: OnlinePeer,
        localPlayer: PlayerID
    ) -> Bool {
        guard assignment.schemaVersion == AppIdentifiers.gameWireSchemaVersion else { return false }
        let players = assignment.seats.map(\.playerID)
        let gamePlayerIDs = assignment.seats.map(\.gamePlayerID)
        return (3...4).contains(assignment.seats.count)
            && assignment.hostPlayerID == sender.playerID
            && players.contains(localPlayer)
            && players.contains(assignment.hostPlayerID)
            && Set(players).count == players.count
            && gamePlayerIDs.allSatisfy { !$0.isEmpty }
            && Set(gamePlayerIDs).count == gamePlayerIDs.count
            && assignment.seats.allSatisfy { !$0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func projectionDecision(
        for envelope: ProjectionEnvelope,
        localPlayer: PlayerID?,
        currentTable: UUID?,
        currentSequence: Int?
    ) -> ProjectionDecision {
        guard envelope.schemaVersion == AppIdentifiers.gameWireSchemaVersion,
              envelope.sequence >= 0,
              let localPlayer,
              let currentTable,
              envelope.viewer == localPlayer,
              envelope.projection.viewer == localPlayer,
              envelope.tableID == currentTable,
              envelope.tableID == envelope.projection.tableID,
              envelope.sequence == envelope.projection.sequence else {
            return .reject
        }

        guard let currentSequence else { return .advance }
        if envelope.sequence < currentSequence { return .reject }
        if envelope.sequence == currentSequence { return .refresh }
        return .advance
    }

    static func frameID(for envelope: ProjectionEnvelope) -> FrameID {
        FrameID(tableID: envelope.tableID, sequence: envelope.sequence)
    }

    /// Relay frames are globally sequenced by the room worker. A client may
    /// receive a frame after reconnecting or after a transient network reorder,
    /// so only a strictly newer server sequence may enter the message stream.
    /// This gate belongs at the transport boundary: projection validation is
    /// intentionally narrower and does not cover hello, seat assignment, or
    /// other wire messages.
    static func acceptsRelaySequence(_ serverSequence: Int?, after lastSequence: Int) -> Bool {
        guard lastSequence >= 0,
              let serverSequence,
              serverSequence > lastSequence else {
            return false
        }
        return true
    }

    static func acceptsHostError(
        _ error: HostErrorEnvelope,
        localPlayer: PlayerID?,
        currentTable: UUID?,
        currentSequence: Int? = nil
    ) -> Bool {
        guard error.schemaVersion == AppIdentifiers.gameWireSchemaVersion,
              error.sequence >= 0,
              let currentTable,
              error.tableID == currentTable,
              currentSequence.map({ error.sequence >= $0 }) ?? true else {
            return false
        }
        return error.recipient == nil || error.recipient == localPlayer
    }

    static func acceptsResyncRequest(
        _ request: ResyncRequestEnvelope,
        sender: OnlinePeer,
        currentTable: UUID?
    ) -> Bool {
        request.schemaVersion == AppIdentifiers.gameWireSchemaVersion
            && request.lastSeenSequence >= 0
            && request.tableID == currentTable
            && request.requester == sender.playerID
    }

    static func acceptsPing(_ ping: PingEnvelope, currentTable: UUID?) -> Bool {
        ping.schemaVersion == AppIdentifiers.gameWireSchemaVersion
            && ping.tableID == currentTable
    }
}
