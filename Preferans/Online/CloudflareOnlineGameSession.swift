import Foundation
import OSLog
import PreferansEngine

private let onlineFlowLogger = Logger(subsystem: "com.mixandmatch.preferans", category: "online-flow")

@MainActor
public final class CloudflareOnlineGameSession: ObservableObject {
    public let roomCode: String
    public let inviteURL: URL
    public let localPeer: OnlinePeer
    public let localCoordinator: RoomOnlineGameCoordinator

    private let transport: CloudflareRoomTransport
    private let rules: PreferansRules
    private let match: MatchSettings
    /// Variant label carried into the worker summary (presentation-only).
    private let variantTag: String?
    /// Present when this session was opened to resume an in-progress game; the
    /// host rebuilds its engine from this instead of dealing fresh.
    private let resume: OnlineResumeContext?

    public init(
        transport: CloudflareRoomTransport,
        inviteURL: URL,
        rules: PreferansRules = .sochi,
        match: MatchSettings = .unbounded,
        botMoveDelay: Duration = BotPacing.interactive,
        coordinator: RoomOnlineGameCoordinator? = nil,
        variantTag: String? = nil,
        resume: OnlineResumeContext? = nil
    ) {
        self.transport = transport
        self.roomCode = transport.roomCode
        self.inviteURL = inviteURL
        self.localPeer = transport.localPeer
        self.rules = rules
        self.match = match
        self.variantTag = variantTag
        self.resume = resume
        self.localCoordinator = coordinator ?? RoomOnlineGameCoordinator(botMoveDelay: botMoveDelay)
    }

    public static func createRoom(
        baseURL: URL = AppIdentifiers.roomWorkerBaseURL,
        inviteBaseURL: URL = AppIdentifiers.inviteBaseURL,
        peers: [OnlinePeer],
        localPlayerID: PlayerID,
        rules: PreferansRules = .sochi,
        match: MatchSettings = .unbounded,
        variantTag: String? = nil,
        botMoveDelay: Duration = BotPacing.interactive
    ) async throws -> CloudflareOnlineGameSession {
        guard let localPeer = peers.first(where: { $0.playerID == localPlayerID }) else {
            throw InMemoryRoom.RoomError.unknownPlayer(localPlayerID)
        }
        let transport = try await CloudflareRoomTransport.createRoom(
            baseURL: baseURL,
            localPeer: localPeer,
            seats: peers,
            maxPlayers: min(max(peers.count, 3), 4)
        )
        logOnlineFlow("event=create roomCode=\(transport.roomCode) local=\(localPeer.playerID.rawValue)")
        return CloudflareOnlineGameSession(
            transport: transport,
            inviteURL: PreferansInviteLink.inviteURL(baseURL: inviteBaseURL, roomCode: transport.roomCode),
            rules: rules,
            match: match,
            botMoveDelay: botMoveDelay,
            variantTag: variantTag
        )
    }

    public static func joinRoom(
        roomCode: String,
        localPeer: OnlinePeer,
        baseURL: URL = AppIdentifiers.roomWorkerBaseURL,
        inviteBaseURL: URL = AppIdentifiers.inviteBaseURL,
        rules: PreferansRules = .sochi,
        match: MatchSettings = .unbounded,
        variantTag: String? = nil,
        botMoveDelay: Duration = BotPacing.interactive
    ) async throws -> CloudflareOnlineGameSession {
        guard let normalizedCode = PreferansInviteLink.normalizedRoomCode(roomCode) else {
            throw CloudflareRoomTransportError.serverError("Room code must be 4-12 letters or numbers.")
        }
        let transport = try await CloudflareRoomTransport.joinRoom(
            baseURL: baseURL,
            roomCode: normalizedCode,
            localPeer: localPeer
        )
        logOnlineFlow("event=join roomCode=\(transport.roomCode) local=\(localPeer.playerID.rawValue)")
        return CloudflareOnlineGameSession(
            transport: transport,
            inviteURL: PreferansInviteLink.inviteURL(baseURL: inviteBaseURL, roomCode: transport.roomCode),
            rules: rules,
            match: match,
            botMoveDelay: botMoveDelay,
            variantTag: variantTag
        )
    }

    /// Resume an in-progress online game from the lobby's "Your games" list.
    /// Rejoins the room (the worker rebinds the original seat by `accountID`),
    /// fetches the durable engine snapshot for that seat, and — when one exists —
    /// carries it as a resume context so the elected host rebuilds the engine
    /// instead of dealing fresh. A missing snapshot (the room is still in its
    /// pre-deal lobby) degrades to a plain rejoin.
    public static func resumeRoom(
        roomCode: String,
        localPeer: OnlinePeer,
        baseURL: URL = AppIdentifiers.roomWorkerBaseURL,
        inviteBaseURL: URL = AppIdentifiers.inviteBaseURL,
        variantTag: String? = nil,
        botMoveDelay: Duration = BotPacing.interactive
    ) async throws -> CloudflareOnlineGameSession {
        guard let normalizedCode = PreferansInviteLink.normalizedRoomCode(roomCode) else {
            throw CloudflareRoomTransportError.serverError("Room code must be 4-12 letters or numbers.")
        }
        let transport = try await CloudflareRoomTransport.joinRoom(
            baseURL: baseURL,
            roomCode: normalizedCode,
            localPeer: localPeer
        )

        var resume: OnlineResumeContext?
        do {
            let payload = try await CloudflareRoomTransport.fetchSnapshot(
                baseURL: baseURL,
                roomCode: normalizedCode,
                playerID: transport.localPeer.playerID
            )
            if let snapshot = payload.decodedSnapshot {
                resume = OnlineResumeContext(snapshot: snapshot, sequence: payload.lastSnapshotSequence)
            }
        } catch {
            // Snapshot unavailable (pre-deal lobby, or transient) — rejoin plainly.
            resume = nil
        }

        logOnlineFlow("event=resume roomCode=\(transport.roomCode) local=\(transport.localPeer.playerID.rawValue) hasSnapshot=\(resume != nil)")
        return CloudflareOnlineGameSession(
            transport: transport,
            inviteURL: PreferansInviteLink.inviteURL(baseURL: inviteBaseURL, roomCode: transport.roomCode),
            rules: resume?.snapshot.rules ?? .sochi,
            match: resume?.snapshot.match ?? .unbounded,
            botMoveDelay: botMoveDelay,
            variantTag: variantTag,
            resume: resume
        )
    }

    public func start() async {
        await localCoordinator.attach(transport: transport, rules: rules, match: match, variantTag: variantTag, resume: resume)
    }

    public func stop() {
        localCoordinator.detach()
        transport.disconnect()
    }
}

private func logOnlineFlow(_ message: String) {
    if ProcessInfo.processInfo.arguments.contains(UITestFlags.onlineFlowLogging) {
        let line = "ONLINE_FLOW \(message)"
        print(line)
        onlineFlowLogger.notice("\(line, privacy: .public)")
    }
}
