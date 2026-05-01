import Foundation
import PreferansEngine

public enum HostGameError: LocalizedError, Sendable, Equatable {
    case wrongTable(expected: UUID, actual: UUID)
    case duplicateClientNonce(UUID)
    case spoofedActor(expected: PlayerID, actual: PlayerID)
    case unknownPlayer(PlayerID)

    public var errorDescription: String? {
        switch self {
        case let .wrongTable(expected, actual):
            return "Wrong table. Expected \(expected), got \(actual)."
        case let .duplicateClientNonce(nonce):
            return "Duplicate action nonce \(nonce)."
        case let .spoofedActor(expected, actual):
            return "Action actor mismatch. Expected \(expected.rawValue), got \(actual.rawValue)."
        case let .unknownPlayer(player):
            return "Unknown player \(player.rawValue)."
        }
    }
}

public struct ValidatedActionRecord: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID { clientNonce }
    public var tableID: UUID
    public var sequence: Int
    public var actor: PlayerID
    public var action: WirePreferansAction
    public var clientNonce: UUID
    public var baseHostSequence: Int
    public var createdAt: Date
    public var eventSummaries: [String]

    public init(
        tableID: UUID,
        sequence: Int,
        actor: PlayerID,
        action: WirePreferansAction,
        clientNonce: UUID,
        baseHostSequence: Int,
        createdAt: Date,
        eventSummaries: [String]
    ) {
        self.tableID = tableID
        self.sequence = sequence
        self.actor = actor
        self.action = action
        self.clientNonce = clientNonce
        self.baseHostSequence = baseHostSequence
        self.createdAt = createdAt
        self.eventSummaries = eventSummaries
    }
}

public struct HostUpdate: Sendable {
    public var tableID: UUID
    public var sequence: Int
    public var projections: [PlayerID: PlayerGameProjection]
    public var eventSummaries: [String]
    public var validatedAction: ValidatedActionRecord?
    public var snapshot: AppEngineSnapshot
    public var status: PreferansGameStatus
}

public actor HostGameActor {
    public nonisolated let tableID: UUID
    public nonisolated let hostPlayerID: PlayerID
    private var engine: PreferansEngine
    private var sequence: Int
    private var seats: [PlayerIdentity]
    private var appliedNonces: Set<UUID>
    private var actionLog: [ValidatedActionRecord]
    private let projectionPolicy: ProjectionPolicy

    public init(
        tableID: UUID = UUID(),
        hostPlayerID: PlayerID,
        seats: [PlayerIdentity],
        rules: PreferansRules = .sochi,
        firstDealer: PlayerID? = nil,
        projectionPolicy: ProjectionPolicy = .online
    ) throws {
        let players = seats.map(\.playerID)
        self.tableID = tableID
        self.hostPlayerID = hostPlayerID
        self.engine = try PreferansEngine(players: players, rules: rules, firstDealer: firstDealer ?? players.first)
        self.sequence = 0
        self.seats = seats
        self.appliedNonces = []
        self.actionLog = []
        self.projectionPolicy = projectionPolicy
    }

    public var players: [PlayerID] { engine.players }
    public var currentSequence: Int { sequence }
    public var currentSnapshot: AppEngineSnapshot { AppEngineSnapshot(engine: engine) }
    public var validatedActionLog: [ValidatedActionRecord] { actionLog }

    public func initialUpdate() -> HostUpdate {
        makeUpdate(events: [], validatedAction: nil)
    }

    /// Applies exactly one client command. The host remains the only owner of the full engine state.
    public func applyClientAction(_ envelope: ClientActionEnvelope, sender: PlayerID?) throws -> HostUpdate {
        guard envelope.tableID == tableID else {
            throw HostGameError.wrongTable(expected: tableID, actual: envelope.tableID)
        }
        guard engine.players.contains(envelope.actor) else {
            throw HostGameError.unknownPlayer(envelope.actor)
        }
        if let sender, sender != envelope.actor, envelope.action.actor != nil {
            throw HostGameError.spoofedActor(expected: sender, actual: envelope.actor)
        }
        guard !appliedNonces.contains(envelope.clientNonce) else {
            throw HostGameError.duplicateClientNonce(envelope.clientNonce)
        }

        let authoritativeAction = makeAuthoritative(envelope.action.action)
        let events = try engine.apply(authoritativeAction)
        sequence += 1
        appliedNonces.insert(envelope.clientNonce)

        let eventSummaries = events.map { String(describing: $0) }
        let record = ValidatedActionRecord(
            tableID: tableID,
            sequence: sequence,
            actor: envelope.actor,
            action: WirePreferansAction(authoritativeAction),
            clientNonce: envelope.clientNonce,
            baseHostSequence: envelope.baseHostSequence,
            createdAt: Date(),
            eventSummaries: eventSummaries
        )
        actionLog.append(record)
        return makeUpdate(events: eventSummaries, validatedAction: record)
    }

    public func projection(for viewer: PlayerID) throws -> PlayerGameProjection {
        guard engine.players.contains(viewer) else {
            throw HostGameError.unknownPlayer(viewer)
        }
        return PlayerProjectionBuilder.projection(
            for: viewer,
            tableID: tableID,
            sequence: sequence,
            engine: engine,
            identities: seats,
            policy: projectionPolicy
        )
    }

    public func fullResync(for viewer: PlayerID) throws -> ProjectionEnvelope {
        let projection = try projection(for: viewer)
        return ProjectionEnvelope(
            tableID: tableID,
            sequence: sequence,
            viewer: viewer,
            projection: projection,
            eventSummaries: []
        )
    }

    private func makeUpdate(events: [String], validatedAction: ValidatedActionRecord?) -> HostUpdate {
        let projections = Dictionary(uniqueKeysWithValues: engine.players.map { player in
            (
                player,
                PlayerProjectionBuilder.projection(
                    for: player,
                    tableID: tableID,
                    sequence: sequence,
                    engine: engine,
                    identities: seats,
                    policy: projectionPolicy
                )
            )
        })
        return HostUpdate(
            tableID: tableID,
            sequence: sequence,
            projections: projections,
            eventSummaries: events,
            validatedAction: validatedAction,
            snapshot: AppEngineSnapshot(engine: engine),
            status: currentStatus
        )
    }

    private var currentStatus: PreferansGameStatus {
        switch engine.state {
        case .waitingForDeal:
            return sequence == 0 ? .lobby : .playing
        case .dealFinished:
            return .playing
        default:
            return .playing
        }
    }

    /// Force startDeal through a host-generated explicit deck and dealer so the validated action log can replay exactly.
    private func makeAuthoritative(_ action: PreferansAction) -> PreferansAction {
        switch action {
        case .startDeal:
            return .startDeal(dealer: engine.nextDealer, deck: Deck.standard32.shuffled())
        default:
            return action
        }
    }
}
