import Foundation
import PreferansEngine

public enum AuthoritativeGameError: LocalizedError, Equatable, Sendable {
    case invalidSchema(Int)
    case commandIDConflict
    case unknownPlayer(PlayerID)
    case duplicateActor(expected: PlayerID, actual: PlayerID)
    case unauthorizedActor(expected: PlayerID, actual: PlayerID)
    case staleSequence(expected: Int, actual: Int)
    case botStalled(PlayerID)
    case botActionLimit

    public var errorDescription: String? {
        switch self {
        case .commandIDConflict:
            return "Command ID was already used for a different command."
        case let .invalidSchema(version):
            return "Unsupported authoritative game schema \(version)."
        case let .unknownPlayer(player):
            return "Unknown player \(player.rawValue)."
        case let .duplicateActor(expected, actual):
            return "Command actor mismatch. Expected \(expected.rawValue), got \(actual.rawValue)."
        case let .unauthorizedActor(expected, actual):
            return "Authenticated sender \(actual.rawValue) cannot control \(expected.rawValue)."
        case let .staleSequence(expected, actual):
            return "Stale command sequence. Expected \(expected), got \(actual)."
        case let .botStalled(player):
            return "Bot \(player.rawValue) did not produce a legal action."
        case .botActionLimit:
            return "Bot cascade exceeded its bounded action limit."
        }
    }
}

public struct AppliedCommandNonce: Codable, Equatable, Sendable {
    public var id: UUID
    public var sequence: Int
    public var sender: PlayerID
    public var actor: PlayerID
    public var action: PreferansAction
    public var baseSequence: Int

    public init(id: UUID, sequence: Int, request: AuthoritativeCommandRequest) {
        self.id = id
        self.sequence = sequence
        self.sender = request.sender
        self.actor = request.actor
        self.action = request.action
        self.baseSequence = request.baseSequence
    }
}

/// Complete private state owned by the room backend. The Worker stores this as
/// an opaque JSON string so UInt64 seeds and hidden hands never pass through
/// JavaScript number conversion or reach a player-controlled device.
public struct AuthoritativeGameState: Codable, Equatable, Sendable {
    public static let schemaVersion = 2
    public static let engineVersion = "preferans-1"

    public var schemaVersion: Int
    public var tableID: UUID
    public var sequence: Int
    public var snapshot: PreferansSnapshot
    public var identities: [PlayerIdentity]
    public var botProfiles: [PlayerID: BotProfile]
    public var appliedNonces: [AppliedCommandNonce]
    public var dealSeed: UInt64
    public var generatedDealCount: UInt64
    public var botInsights: [BotDecisionExplanation]

    public init(
        tableID: UUID = UUID(),
        sequence: Int = 0,
        snapshot: PreferansSnapshot,
        identities: [PlayerIdentity],
        botProfiles: [PlayerID: BotProfile] = [:],
        appliedNonces: [AppliedCommandNonce] = [],
        dealSeed: UInt64,
        generatedDealCount: UInt64 = 0,
        botInsights: [BotDecisionExplanation] = []
    ) {
        self.schemaVersion = Self.schemaVersion
        self.tableID = tableID
        self.sequence = sequence
        self.snapshot = snapshot
        self.identities = identities
        self.botProfiles = botProfiles
        self.appliedNonces = appliedNonces
        self.dealSeed = dealSeed
        self.generatedDealCount = generatedDealCount
        self.botInsights = botInsights
    }
}

public struct CreateAuthoritativeGameRequest: Codable, Equatable, Sendable {
    /// Optional stable room identity. The Durable Object reuses it while a
    /// schema-v3 lobby roster changes before the first deal.
    public var tableID: UUID?
    public var identities: [PlayerIdentity]
    public var rules: PreferansRules
    public var match: MatchSettings
    public var firstDealer: PlayerID?
    public var botProfiles: [PlayerID: BotProfile]

    public init(
        tableID: UUID? = nil,
        identities: [PlayerIdentity],
        rules: PreferansRules = .sochi,
        match: MatchSettings = .unbounded,
        firstDealer: PlayerID? = nil,
        botProfiles: [PlayerID: BotProfile] = [:]
    ) {
        self.tableID = tableID
        self.identities = identities
        self.rules = rules
        self.match = match
        self.firstDealer = firstDealer
        self.botProfiles = botProfiles
    }
}

public struct AuthoritativeCommandRequest: Codable, Equatable, Sendable {
    /// Opaque state returned by the previous server transition.
    public var state: String
    /// Canonical seat derived by the Durable Object from the socket token.
    public var sender: PlayerID
    /// Seat the action speaks for. This differs from sender only for the
    /// explicitly supported open-dummy controller relationship.
    public var actor: PlayerID
    public var action: PreferansAction
    public var clientNonce: UUID
    public var baseSequence: Int

    public init(
        state: String,
        sender: PlayerID,
        actor: PlayerID,
        action: PreferansAction,
        clientNonce: UUID,
        baseSequence: Int
    ) {
        self.state = state
        self.sender = sender
        self.actor = actor
        self.action = action
        self.clientNonce = clientNonce
        self.baseSequence = baseSequence
    }
}

public struct AuthoritativeGameResponse: Codable, Equatable, Sendable {
    public var engineVersion: String = AuthoritativeGameState.engineVersion
    public var botPending: Bool = false
    public var state: String
    public var sequence: Int
    public var projections: [ProjectionEnvelope]
    public var status: PreferansGameStatus
    public var dealNumber: Int
    public var phase: String

    public init(
        state: String,
        sequence: Int,
        projections: [ProjectionEnvelope],
        status: PreferansGameStatus,
        dealNumber: Int,
        phase: String
    ) {
        self.state = state
        self.sequence = sequence
        self.projections = projections
        self.status = status
        self.dealNumber = dealNumber
        self.phase = phase
    }
}

public enum AuthoritativeGameService {
    public static let maximumRememberedNonces = 2_048
    public static let maximumBotActionsPerCommand = 512

    public static func create(
        _ request: CreateAuthoritativeGameRequest,
        tableID: UUID = UUID(),
        dealSeed: UInt64
    ) throws -> AuthoritativeGameResponse {
        let players = request.identities.map(\.playerID)
        let engine = try PreferansEngine(
            players: players,
            rules: request.rules,
            match: request.match,
            firstDealer: request.firstDealer
        )
        let state = AuthoritativeGameState(
            tableID: tableID,
            snapshot: engine.snapshot,
            identities: request.identities,
            botProfiles: request.botProfiles,
            dealSeed: dealSeed
        )
        return try response(for: state, events: [])
    }

    public static func apply(
        _ request: AuthoritativeCommandRequest,
        strategyFactory: @Sendable (BotProfile) -> any PlayerStrategy = { HeuristicStrategy(profile: $0) }
    ) async throws -> AuthoritativeGameResponse {
        var state = try decodeState(request.state)
        guard state.schemaVersion == AuthoritativeGameState.schemaVersion else {
            throw AuthoritativeGameError.invalidSchema(state.schemaVersion)
        }

        var engine = try PreferansEngine(snapshot: state.snapshot)
        guard engine.players.contains(request.actor) else {
            throw AuthoritativeGameError.unknownPlayer(request.actor)
        }

        try authorize(
            sender: request.sender,
            claimedActor: request.actor,
            action: request.action,
            engine: engine
        )
        if let receipt = state.appliedNonces.first(where: { $0.id == request.clientNonce }) {
            guard receipt.sender == request.sender, receipt.actor == request.actor,
                  receipt.action == request.action, receipt.baseSequence == request.baseSequence else {
                throw AuthoritativeGameError.commandIDConflict
            }
            return try response(for: state, events: [])
        }
        guard request.baseSequence == state.sequence else {
            throw AuthoritativeGameError.staleSequence(
                expected: state.sequence,
                actual: request.baseSequence
            )
        }

        let action = authoritativeAction(request.action, state: &state)
        let events = try engine.apply(action)
        state.sequence += 1
        state.appliedNonces.append(.init(id: request.clientNonce, sequence: state.sequence, request: request))
        if state.appliedNonces.count > maximumRememberedNonces {
            state.appliedNonces.removeFirst(state.appliedNonces.count - maximumRememberedNonces)
        }
        state.snapshot = engine.snapshot

        state.snapshot = engine.snapshot
        return try response(for: state, events: events)
    }

    /// One durable scheduled move. A retry evaluates the same input revision.
    public static func advanceBot(state blob: String) async throws -> AuthoritativeGameResponse {
        var state = try decodeState(blob)
        guard state.schemaVersion == AuthoritativeGameState.schemaVersion else {
            throw AuthoritativeGameError.invalidSchema(state.schemaVersion)
        }
        var engine = try PreferansEngine(snapshot: state.snapshot)
        let events = try await advanceBots(engine: &engine, state: &state,
            strategyFactory: { HeuristicStrategy(profile: $0) })
        state.snapshot = engine.snapshot
        return try response(for: state, events: events)
    }

    public static func encodeState(_ state: AuthoritativeGameState) throws -> String {
        String(decoding: try encoder.encode(state), as: UTF8.self)
    }

    public static func decodeState(_ blob: String) throws -> AuthoritativeGameState {
        try decoder.decode(AuthoritativeGameState.self, from: Data(blob.utf8))
    }

    private static func authorize(
        sender: PlayerID,
        claimedActor: PlayerID,
        action: PreferansAction,
        engine: PreferansEngine
    ) throws {
        if let actionActor = action.actor, actionActor != claimedActor {
            throw AuthoritativeGameError.duplicateActor(
                expected: claimedActor,
                actual: actionActor
            )
        }
        let controlledActor = action.actor ?? claimedActor
        let expectedSender = engine.controllingActor(of: controlledActor)
        guard sender == expectedSender else {
            throw AuthoritativeGameError.unauthorizedActor(
                expected: expectedSender,
                actual: sender
            )
        }
    }

    private static func authoritativeAction(
        _ action: PreferansAction,
        state: inout AuthoritativeGameState
    ) -> PreferansAction {
        guard case .startDeal = action else { return action }
        let seed = state.dealSeed &+ (state.generatedDealCount &* 0x9E37_79B9_7F4A_7C15)
        state.generatedDealCount &+= 1
        return .startDeal(
            dealer: state.snapshot.nextDealer,
            deck: Deck.shuffled(seed: seed)
        )
    }

    private static func advanceBots(
        engine: inout PreferansEngine,
        state: inout AuthoritativeGameState,
        strategyFactory: @Sendable (BotProfile) -> any PlayerStrategy
    ) async throws -> [PreferansEvent] {
        var events: [PreferansEvent] = []
        var actionCount = 0

        while let actor = engine.state.currentActor {
            let controller = engine.controllingActor(of: actor)
            guard let profile = state.botProfiles[controller] else { break }
            guard actionCount < maximumBotActionsPerCommand else {
                throw AuthoritativeGameError.botActionLimit
            }
            let snapshot = engine.snapshot
            let proposed = await strategyFactory(profile).decision(
                snapshot: snapshot,
                viewer: controller
            )
            guard let decision = BotDecisionRecovery.recover(
                proposed,
                snapshot: snapshot,
                viewer: controller
            ) else {
                throw AuthoritativeGameError.botStalled(controller)
            }
            events.append(contentsOf: try engine.apply(decision.action))
            state.sequence += 1
            if let explanation = decision.explanation {
                state.botInsights.append(explanation)
                if state.botInsights.count > 20 {
                    state.botInsights.removeFirst(state.botInsights.count - 20)
                }
            }
            state.snapshot = engine.snapshot
            actionCount += 1
            break // pacing and continuation belong to the durable room alarm
        }
        return events
    }

    private static func response(
        for state: AuthoritativeGameState,
        events: [PreferansEvent]
    ) throws -> AuthoritativeGameResponse {
        let engine = try PreferansEngine(snapshot: state.snapshot)
        let projections = engine.players.map { player in
            let projection = PlayerProjectionBuilder.projection(
                for: player,
                tableID: state.tableID,
                sequence: state.sequence,
                engine: engine,
                identities: state.identities,
                policy: .online
            )
            return ProjectionEnvelope(
                tableID: state.tableID,
                sequence: state.sequence,
                viewer: player,
                projection: projection,
                eventSummaries: [],
                events: OnlineEventProjection.events(events, for: player),
                botInsights: state.botInsights
            )
        }
        var result = AuthoritativeGameResponse(
            state: try encodeState(state),
            sequence: state.sequence,
            projections: projections,
            status: status(for: engine, sequence: state.sequence),
            dealNumber: engine.dealsPlayed + 1,
            phase: projections.first?.projection.phase.token ?? "waitingForDeal"
        )
        if let actor = engine.state.currentActor {
            result.botPending = state.botProfiles[engine.controllingActor(of: actor)] != nil
        }
        return result
    }

    private static func status(
        for engine: PreferansEngine,
        sequence: Int
    ) -> PreferansGameStatus {
        switch engine.state {
        case .waitingForDeal:
            return sequence == 0 ? .lobby : .playing
        case .gameOver:
            return .finished
        default:
            return .playing
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
