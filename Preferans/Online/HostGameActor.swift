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

/// A pending bot move the host owes for one of its bot-driven seats. Produced
/// inside ``HostGameActor`` (which owns the full engine and so can hand out a
/// complete ``PreferansSnapshot`` — hidden hands included — that the strategy
/// needs), then carried back to the `@MainActor` coordinator which paces the
/// decision off-actor and applies it. `decider` is the *controlling* seat: for
/// most phases that equals the seat whose turn it is, but in single-whist
/// greedy play the lone whister plays the passer's cards, so `decider` names
/// the whister.
public struct BotDecisionPlan: Sendable {
    public let decider: PlayerID
    public let snapshot: PreferansSnapshot
    public let baseSequence: Int
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

    public init(
        tableID: UUID,
        hostPlayerID: PlayerID,
        seats: [PlayerIdentity],
        rules: PreferansRules = .sochi,
        firstDealer: PlayerID? = nil,
        validatedActionLog records: [ValidatedActionRecord],
        projectionPolicy: ProjectionPolicy = .online,
        dealSource: DealSource = RandomDealSource()
    ) throws {
        let players = seats.map(\.playerID)
        if let wrongTable = records.first(where: { $0.tableID != tableID }) {
            throw HostGameError.wrongTable(expected: tableID, actual: wrongTable.tableID)
        }
        self.tableID = tableID
        self.hostPlayerID = hostPlayerID
        self.engine = try GameLogReplayer.replay(
            players: players,
            rules: rules,
            firstDealer: firstDealer ?? players.first,
            records: records
        )
        self.sequence = records.map(\.sequence).max() ?? 0
        self.seats = seats
        self.appliedNonces = Set(records.map(\.clientNonce))
        self.actionLog = records.sorted { $0.sequence < $1.sequence }
        self.projectionPolicy = projectionPolicy
        self.dealSource = dealSource
    }

    public var players: [PlayerID] { engine.players }
    public var currentSequence: Int { sequence }
    public var currentSnapshot: AppEngineSnapshot { AppEngineSnapshot(engine: engine) }
    public var validatedActionLog: [ValidatedActionRecord] { actionLog }

    public func updateIdentities(_ identities: [PlayerIdentity]) {
        let replacements = Dictionary(uniqueKeysWithValues: identities.map { ($0.playerID, $0) })
        seats = seats.map { replacements[$0.playerID] ?? $0 }
    }

    /// The bot move (if any) the host currently owes. Returns `nil` when no seat
    /// is on the clock (between deals, match over) or when the controlling seat
    /// is a human — only seats in `botSeats` are auto-played. The returned
    /// snapshot is captured at call time; the coordinator re-checks
    /// ``stillAwaiting(_:)`` after pacing/deciding so a stale decision is never
    /// applied.
    public func nextBotDecisionPlan(botSeats: Set<PlayerID>) -> BotDecisionPlan? {
        guard let actor = engine.state.currentActor else { return nil }
        let decider = engine.controllingActor(of: actor)
        guard botSeats.contains(decider) else { return nil }
        return BotDecisionPlan(decider: decider, snapshot: engine.snapshot, baseSequence: sequence)
    }

    /// True while the engine is still in the exact `state` a bot decision was
    /// computed against — the same snapshot-equality guard the local loop uses
    /// (`GameViewModel.scheduleBotIfNeeded`) to drop a move that a concurrent
    /// human action superseded.
    public func stillAwaiting(_ state: DealState) -> Bool {
        engine.state == state
    }

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
            // The action speaks for `actionActor`. The wire sender may be
            // either that seat itself or — in single-whist greedy play —
            // the lone whister speaking for a passer they control. Any
            // other sender is rejected as spoofed.
            if let sender, sender != envelope.actor {
                let controller = engine.controllingActor(of: envelope.actor)
                if sender != controller {
                    throw HostGameError.spoofedActor(expected: controller, actual: sender)
                }
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
