import Foundation
import PreferansEngine

@MainActor
public final class InMemoryRoom {
    public enum RoomError: LocalizedError, Equatable {
        case unknownPlayer(PlayerID)

        public var errorDescription: String? {
            switch self {
            case let .unknownPlayer(player):
                return "Unknown in-memory room player \(player.rawValue)."
            }
        }
    }

    public let code: String
    public let peers: [OnlinePeer]
    public let hostPlayerID: PlayerID
    private var transports: [PlayerID: InMemoryRoomTransport] = [:]

    public init(code: String = "TESTROOM", peers: [OnlinePeer], hostPlayerID: PlayerID? = nil) {
        precondition(!peers.isEmpty, "InMemoryRoom requires at least one peer.")
        self.code = code
        self.peers = peers
        self.hostPlayerID = hostPlayerID ?? peers.sorted { $0.playerID.rawValue < $1.playerID.rawValue }[0].playerID
    }

    public func transport(for playerID: PlayerID) throws -> InMemoryRoomTransport {
        guard let peer = peers.first(where: { $0.playerID == playerID }) else {
            throw RoomError.unknownPlayer(playerID)
        }
        if let existing = transports[playerID] {
            return existing
        }
        let transport = InMemoryRoomTransport(room: self, localPeer: peer)
        transports[playerID] = transport
        return transport
    }

    fileprivate func hostPeer() -> OnlinePeer? {
        peers.first { $0.playerID == hostPlayerID }
    }

    fileprivate func deliver(_ message: GameWireMessage, from sender: OnlinePeer, to recipients: [OnlinePeer]) {
        for recipient in recipients where recipient.playerID != sender.playerID {
            transports[recipient.playerID]?.receive(ReceivedRoomMessage(message: message, sender: sender))
        }
    }
}

@MainActor
public final class InMemoryRoomTransport: RoomRealtimeTransport {
    public let localPeer: OnlinePeer
    private let room: InMemoryRoom
    private var continuations: [UUID: AsyncStream<ReceivedRoomMessage>.Continuation] = [:]
    private var backlog: [ReceivedRoomMessage] = []
    private var isDisconnected = false

    fileprivate init(room: InMemoryRoom, localPeer: OnlinePeer) {
        self.room = room
        self.localPeer = localPeer
    }

    public var participants: [OnlinePeer] {
        room.peers
    }

    public func chooseHost() async -> OnlinePeer? {
        room.hostPeer()
    }

    public func messages() -> AsyncStream<ReceivedRoomMessage> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            for message in backlog {
                continuation.yield(message)
            }
            backlog.removeAll()
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations.removeValue(forKey: id) }
            }
        }
    }

    public func send(_ message: GameWireMessage, to peers: [OnlinePeer], reliably: Bool = true) async throws {
        guard !isDisconnected else { return }
        room.deliver(message, from: localPeer, to: peers)
    }

    public func sendToAll(_ message: GameWireMessage, reliably: Bool = true) async throws {
        guard !isDisconnected else { return }
        room.deliver(message, from: localPeer, to: room.peers)
    }

    public func disconnect() {
        isDisconnected = true
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
        backlog.removeAll()
    }

    fileprivate func receive(_ message: ReceivedRoomMessage) {
        guard !isDisconnected else { return }
        if continuations.isEmpty {
            backlog.append(message)
        } else {
            for continuation in continuations.values {
                continuation.yield(message)
            }
        }
    }
}
