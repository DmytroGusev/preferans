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
        let players = assignment.seats.map(\.playerID)
        return assignment.hostPlayerID == sender.playerID
            && players.contains(localPlayer)
            && players.contains(assignment.hostPlayerID)
            && Set(players).count == players.count
    }

    static func projectionDecision(
        for envelope: ProjectionEnvelope,
        localPlayer: PlayerID?,
        currentTable: UUID?,
        currentSequence: Int?
    ) -> ProjectionDecision {
        guard envelope.sequence >= 0,
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

    static func acceptsHostError(
        _ error: HostErrorEnvelope,
        localPlayer: PlayerID?,
        currentTable: UUID?,
        currentSequence: Int? = nil
    ) -> Bool {
        guard error.sequence >= 0,
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
        request.tableID == currentTable && request.requester == sender.playerID
    }

    static func acceptsPing(_ ping: PingEnvelope, currentTable: UUID?) -> Bool {
        ping.tableID == currentTable
    }
}
