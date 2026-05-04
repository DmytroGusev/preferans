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
    public var action: PreferansAction
    public var clientNonce: UUID
    public var baseHostSequence: Int
    public var createdAt: Date
    /// Structured domain events emitted by applying `action`. This is the
    /// append-only source for audit/replay; `eventSummaries` is a lossy UI
    /// projection kept for older records and simple logs.
    public var events: [PreferansEvent]
    public var eventSummaries: [String]

    public init(
        tableID: UUID,
        sequence: Int,
        actor: PlayerID,
        action: PreferansAction,
        clientNonce: UUID,
        baseHostSequence: Int,
        createdAt: Date,
        events: [PreferansEvent],
        eventSummaries: [String]? = nil
    ) {
        self.tableID = tableID
        self.sequence = sequence
        self.actor = actor
        self.action = action
        self.clientNonce = clientNonce
        self.baseHostSequence = baseHostSequence
        self.createdAt = createdAt
        self.events = events
        self.eventSummaries = eventSummaries ?? Self.summaries(for: events)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tableID = try container.decode(UUID.self, forKey: .tableID)
        self.sequence = try container.decode(Int.self, forKey: .sequence)
        self.actor = try container.decode(PlayerID.self, forKey: .actor)
        self.action = try container.decode(PreferansAction.self, forKey: .action)
        self.clientNonce = try container.decode(UUID.self, forKey: .clientNonce)
        self.baseHostSequence = try container.decode(Int.self, forKey: .baseHostSequence)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.events = try container.decodeIfPresent([PreferansEvent].self, forKey: .events) ?? []
        self.eventSummaries = try container.decodeIfPresent([String].self, forKey: .eventSummaries)
            ?? Self.summaries(for: events)
    }

    private enum CodingKeys: String, CodingKey {
        case tableID
        case sequence
        case actor
        case action
        case clientNonce
        case baseHostSequence
        case createdAt
        case events
        case eventSummaries
    }

    public static func summaries(for events: [PreferansEvent]) -> [String] {
        events.map { String(describing: $0) }
    }
}

public struct HostUpdate: Sendable {
    public var tableID: UUID
    public var sequence: Int
    public var projections: [PlayerID: PlayerGameProjection]
    public var events: [PreferansEvent]
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
    private let dealSource: DealSource

    public init(
        tableID: UUID = UUID(),
        hostPlayerID: PlayerID,
        seats: [PlayerIdentity],
        rules: PreferansRules = .sochi,
        firstDealer: PlayerID? = nil,
        projectionPolicy: ProjectionPolicy = .online,
        dealSource: DealSource = RandomDealSource()
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
        self.dealSource = dealSource
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
        if let actionActor = envelope.action.actor {
            if envelope.actor != actionActor {
                throw HostGameError.spoofedActor(expected: envelope.actor, actual: actionActor)
            }
            if let sender, sender != envelope.actor {
                throw HostGameError.spoofedActor(expected: sender, actual: envelope.actor)
            }
        }
        guard !appliedNonces.contains(envelope.clientNonce) else {
            throw HostGameError.duplicateClientNonce(envelope.clientNonce)
        }

        let authoritativeAction = makeAuthoritative(envelope.action)
        let events = try engine.apply(authoritativeAction)
        sequence += 1
        appliedNonces.insert(envelope.clientNonce)

        let eventSummaries = ValidatedActionRecord.summaries(for: events)
        let record = ValidatedActionRecord(
            tableID: tableID,
            sequence: sequence,
            actor: envelope.actor,
            action: authoritativeAction,
            clientNonce: envelope.clientNonce,
            baseHostSequence: envelope.baseHostSequence,
            createdAt: Date(),
            events: events,
            eventSummaries: eventSummaries
        )
        actionLog.append(record)
        return makeUpdate(events: events, validatedAction: record)
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
            eventSummaries: [],
            events: []
        )
    }

    private func makeUpdate(events: [PreferansEvent], validatedAction: ValidatedActionRecord?) -> HostUpdate {
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
            events: events,
            eventSummaries: ValidatedActionRecord.summaries(for: events),
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
            return .startDeal(dealer: engine.nextDealer, deck: dealSource.nextDeck())
        default:
            return action
        }
    }
}
