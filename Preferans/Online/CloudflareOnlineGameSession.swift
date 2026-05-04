import Foundation
import PreferansEngine

@MainActor
public final class CloudflareOnlineGameSession: ObservableObject {
    public let roomCode: String
    public let inviteURL: URL
    public let localPeer: OnlinePeer
    public let localCoordinator: RoomOnlineGameCoordinator

    private let transport: CloudflareRoomTransport
    private let rules: PreferansRules

    public init(
        transport: CloudflareRoomTransport,
        inviteURL: URL,
        rules: PreferansRules = .sochi,
        coordinator: RoomOnlineGameCoordinator? = nil
    ) {
        self.transport = transport
        self.roomCode = transport.roomCode
        self.inviteURL = inviteURL
        self.localPeer = transport.localPeer
        self.rules = rules
        self.localCoordinator = coordinator ?? RoomOnlineGameCoordinator()
    }

    public static func createRoom(
        baseURL: URL = AppIdentifiers.roomWorkerBaseURL,
        inviteBaseURL: URL = AppIdentifiers.inviteBaseURL,
        peers: [OnlinePeer],
        localPlayerID: PlayerID,
        rules: PreferansRules = .sochi
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
        return CloudflareOnlineGameSession(
            transport: transport,
            inviteURL: PreferansInviteLink.inviteURL(baseURL: inviteBaseURL, roomCode: transport.roomCode),
            rules: rules
        )
    }

    public static func joinRoom(
        roomCode: String,
        localPeer: OnlinePeer,
        baseURL: URL = AppIdentifiers.roomWorkerBaseURL,
        inviteBaseURL: URL = AppIdentifiers.inviteBaseURL,
        rules: PreferansRules = .sochi
    ) async throws -> CloudflareOnlineGameSession {
        guard let normalizedCode = PreferansInviteLink.normalizedRoomCode(roomCode) else {
            throw CloudflareRoomTransportError.serverError("Room code must be 4-12 letters or numbers.")
        }
        let transport = try await CloudflareRoomTransport.joinRoom(
            baseURL: baseURL,
            roomCode: normalizedCode,
            localPeer: localPeer
        )
        return CloudflareOnlineGameSession(
            transport: transport,
            inviteURL: PreferansInviteLink.inviteURL(baseURL: inviteBaseURL, roomCode: transport.roomCode),
            rules: rules
        )
    }

    public func start() async {
        await localCoordinator.attach(transport: transport, rules: rules)
    }

    public func stop() {
        localCoordinator.detach()
        transport.disconnect()
    }
}
