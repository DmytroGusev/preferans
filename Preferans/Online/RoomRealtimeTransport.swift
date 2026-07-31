import Foundation
import PreferansEngine

public enum OnlineAccountProvider: String, Codable, Sendable, Equatable {
    case gameCenter
    case apple
    case guest
    case email
    case dev
}

public struct OnlinePeer: Codable, Sendable, Hashable, Identifiable {
    public var id: PlayerID { playerID }
    public var playerID: PlayerID
    public var accountID: String
    public var provider: OnlineAccountProvider
    public var displayName: String

    public init(
        playerID: PlayerID,
        accountID: String,
        provider: OnlineAccountProvider,
        displayName: String
    ) {
        self.playerID = playerID
        self.accountID = accountID
        self.provider = provider
        self.displayName = displayName
    }

    public var playerIdentity: PlayerIdentity {
        PlayerIdentity(playerID: playerID, gamePlayerID: accountID, displayName: displayName)
    }
}

public extension OnlinePeer {
    /// Account-ID prefix the host stamps on a seat it has reserved but nobody
    /// has claimed yet. The room server fills the first such seat on join
    /// (binding by `accountID`), so this must stay in sync with the worker's
    /// `PENDING_ACCOUNT_PREFIX`.
    static let pendingAccountPrefix = "pending:"

    /// Account-ID prefix for a seat the host fills with a server-side bot it
    /// drives itself. Unlike `pending:` seats, a `bot:` seat is *not* open: the
    /// room worker treats any non-`pending:` accountID as occupied, so a late
    /// human can never claim a bot's seat (kept in sync with the worker comment
    /// next to `PENDING_ACCOUNT_PREFIX`). Bots have no socket — they consume
    /// state through the host's in-process engine, never the wire.
    static let botAccountPrefix = "bot:"

    /// A reserved-but-unclaimed seat — a placeholder the host advertised for a
    /// friend who hasn't taken it yet.
    var isPendingSeat: Bool { accountID.hasPrefix(Self.pendingAccountPrefix) }

    /// A seat the host fills with a server-side bot.
    var isBotSeat: Bool { accountID.hasPrefix(Self.botAccountPrefix) }
}

/// One seat as shown in the pre-deal online waiting room. Lets the waiting-room
/// UI render occupancy (who's here, who's still open) without reaching into the
/// coordinator's private peer map.
public struct WaitingRoomSeat: Identifiable, Equatable, Sendable {
    public enum Occupancy: Equatable, Sendable {
        /// This device's own seat.
        case you(name: String)
        /// A different human who has joined.
        case human(name: String)
        /// A host-driven bot, named so the waiting room matches the
        /// "Bot 2"/"Bot 3" labels the live table will show.
        case bot(name: String)
        /// A reserved seat nobody has joined yet (`pending:`).
        case openWaiting

        public var isBot: Bool {
            if case .bot = self { return true }
            return false
        }
    }

    public var player: PlayerID
    public var occupancy: Occupancy
    public var id: PlayerID { player }

    public init(player: PlayerID, occupancy: Occupancy) {
        self.player = player
        self.occupancy = occupancy
    }
}

public struct ReceivedRoomMessage: Sendable {
    public var message: GameWireMessage
    public var sender: OnlinePeer

    public init(message: GameWireMessage, sender: OnlinePeer) {
        self.message = message
        self.sender = sender
    }
}

/// What a host needs to resume an in-progress online game from the
/// Durable-Object-backed snapshot: the authoritative engine state and the host
/// sequence to continue numbering from. The table identity is re-minted on
/// resume and re-broadcast via seat assignment — the worker keys by room code,
/// so the original UUID never needs to survive.
public struct OnlineResumeContext: Sendable {
    public var snapshot: PreferansSnapshot
    public var sequence: Int

    public init(snapshot: PreferansSnapshot, sequence: Int) {
        self.snapshot = snapshot
        self.sequence = sequence
    }
}

@MainActor
public protocol RoomRealtimeTransport: AnyObject {
    var localPeer: OnlinePeer { get }
    var participants: [OnlinePeer] { get }

    func chooseHost() async -> OnlinePeer?
    func messages() -> AsyncStream<ReceivedRoomMessage>
    /// A stream of roster snapshots, emitted whenever the room's authority pushes
    /// a new membership (the relay's presence broadcast). The waiting room is
    /// driven off this so an already-connected client reflects later joins and
    /// leaves instead of freezing on the roster it saw at its own join. Transports
    /// with no server-pushed presence inherit the default empty stream.
    func participantUpdates() -> AsyncStream<[OnlinePeer]>
    /// Socket lifecycle events that affect player-facing recovery UX.
    func connectionEvents() -> AsyncStream<RoomTransportEvent>
    func send(_ message: GameWireMessage, to peers: [OnlinePeer], reliably: Bool) async throws
    func sendToAll(_ message: GameWireMessage, reliably: Bool) async throws
    /// Ask the room's authority to convert every still-open (`pending:`) seat into
    /// a host-driven bot. Returns the updated roster when the transport owns a
    /// server-side authority that performed the change (Cloudflare), or `nil` when
    /// the caller should fall back to converting seats locally (in-memory/GameKit).
    func fillPendingSeatsWithBots() async throws -> [OnlinePeer]?
    /// Durable engine state to adopt if the room authority elects this device
    /// as a replacement host. Local transports have no remote snapshot.
    func hostRecoveryContext() async throws -> OnlineResumeContext?
    /// Commit the host's authoritative snapshot before its projections are
    /// exposed. Relay-backed transports persist it; local transports are an
    /// intentional no-op.
    func reportState(
        status: PreferansGameStatus,
        summary: OnlineStateSummary,
        snapshot: PreferansSnapshot?,
        snapshotSequence: Int
    ) async throws
    func disconnect()
}

public extension RoomRealtimeTransport {
    /// Default: no server-pushed presence, so the roster is fixed at attach time.
    func participantUpdates() -> AsyncStream<[OnlinePeer]> {
        AsyncStream { $0.finish() }
    }

    func connectionEvents() -> AsyncStream<RoomTransportEvent> {
        AsyncStream { $0.finish() }
    }

    /// Default: no server-side seat authority — the caller converts seats itself.
    func fillPendingSeatsWithBots() async throws -> [OnlinePeer]? { nil }

    /// Local/in-memory transports elect a fixed host and never recover from a
    /// server snapshot.
    func hostRecoveryContext() async throws -> OnlineResumeContext? { nil }

    func reportState(
        status: PreferansGameStatus,
        summary: OnlineStateSummary,
        snapshot: PreferansSnapshot?,
        snapshotSequence: Int
    ) async throws {}
}

/// Whether this client is currently hearing back from the authoritative host.
/// The host itself is always `.live`; only clients move through these states.
public enum OnlineLiveness: Equatable, Sendable {
    /// Attached to the table but no host response observed yet.
    case connecting
    /// The host answered within the heartbeat window.
    case live
    /// No host response within `HeartbeatConfig.hostTimeout` — the table is stalled.
    case hostUnreachable
}

public enum RoomTransportEvent: Equatable, Sendable {
    /// A socket frame was received, proving the current connection is usable.
    case connected
    /// A transient transport failure is being retried automatically.
    case reconnecting
    /// The same account rejoined this seat and rotated its room credential.
    case seatTakenOver
}

public enum OnlineTransportStatus: Equatable, Sendable {
    case connecting
    case connected
    case reconnecting
    case seatTakenOver
    case disconnected
}

/// Cadence for the client-side host heartbeat. Injectable so unit tests and the
/// in-memory/demo room — which has no real socket to lose — can run with fast or
/// disabled timing instead of the production interval.
public struct HeartbeatConfig: Sendable, Equatable {
    public var interval: Duration
    public var hostTimeout: Duration
    public var isEnabled: Bool

    public init(interval: Duration, hostTimeout: Duration, isEnabled: Bool = true) {
        self.interval = interval
        self.hostTimeout = hostTimeout
        self.isEnabled = isEnabled
    }

    /// Production cadence: probe the host every 3s, flag it after 10s of silence.
    public static let `default` = HeartbeatConfig(interval: .seconds(3), hostTimeout: .seconds(10))
    /// No heartbeat — for the in-process room and tests that don't exercise liveness.
    public static let disabled = HeartbeatConfig(interval: .seconds(3), hostTimeout: .seconds(10), isEnabled: false)
}
