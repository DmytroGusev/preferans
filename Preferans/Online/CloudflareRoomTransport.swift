import Foundation
import PreferansEngine

public struct CloudflareRoomSummary: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var roomCode: String
    public var hostPlayerID: PlayerID
    public var peers: [OnlinePeer]
    public var maxPlayers: Int
    public var createdAt: String
    public var updatedAt: String
    public var relaySequence: Int
    public var websocketURL: URL?
}

public enum CloudflareRoomTransportError: LocalizedError {
    case missingSocketURL
    case invalidHTTPResponse
    case serverError(String)
    case socketNotConnected
    case invalidSocketMessage

    public var errorDescription: String? {
        switch self {
        case .missingSocketURL:
            return "Room response did not include a WebSocket URL."
        case .invalidHTTPResponse:
            return "Room server returned an invalid response."
        case let .serverError(message):
            return message
        case .socketNotConnected:
            return "Room WebSocket is not connected."
        case .invalidSocketMessage:
            return "Room WebSocket sent an unsupported message."
        }
    }
}

@MainActor
public final class CloudflareRoomTransport: ObservableObject, RoomRealtimeTransport {
    public let baseURL: URL
    public let roomCode: String
    public let localPeer: OnlinePeer

    @Published public private(set) var participants: [OnlinePeer]
    @Published public private(set) var hostPlayerID: PlayerID
    @Published public private(set) var lastError: String?

    private let socketURL: URL
    private let session: URLSession
    private var socketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var continuations: [UUID: AsyncStream<ReceivedRoomMessage>.Continuation] = [:]

    private var encoder: JSONEncoder { PreferansJSONCoder.encoder }
    private var decoder: JSONDecoder { PreferansJSONCoder.decoder }

    public init(baseURL: URL, summary: CloudflareRoomSummary, localPeer: OnlinePeer, session: URLSession = .shared) throws {
        guard let socketURL = summary.websocketURL else {
            throw CloudflareRoomTransportError.missingSocketURL
        }
        self.baseURL = baseURL
        self.roomCode = summary.roomCode
        self.localPeer = localPeer
        self.participants = summary.peers
        self.hostPlayerID = summary.hostPlayerID
        self.socketURL = socketURL
        self.session = session
    }

    deinit {
        receiveTask?.cancel()
    }

    public static func createRoom(
        baseURL: URL,
        localPeer: OnlinePeer,
        seats: [OnlinePeer],
        maxPlayers: Int = 4,
        session: URLSession = .shared
    ) async throws -> CloudflareRoomTransport {
        let request = CreateRoomRequest(localPeer: localPeer, seats: seats, maxPlayers: maxPlayers)
        let summary = try await postRoomRequest(request, to: endpoint(baseURL, "rooms"), session: session)
        return try CloudflareRoomTransport(baseURL: baseURL, summary: summary, localPeer: localPeer, session: session)
    }

    public static func joinRoom(
        baseURL: URL,
        roomCode: String,
        localPeer: OnlinePeer,
        session: URLSession = .shared
    ) async throws -> CloudflareRoomTransport {
        let request = JoinRoomRequest(localPeer: localPeer)
        let summary = try await postRoomRequest(request, to: endpoint(baseURL, "rooms", roomCode, "join"), session: session)
        return try CloudflareRoomTransport(baseURL: baseURL, summary: summary, localPeer: localPeer, session: session)
    }

    public func chooseHost() async -> OnlinePeer? {
        participants.first { $0.playerID == hostPlayerID }
    }

    public func messages() -> AsyncStream<ReceivedRoomMessage> {
        connectIfNeeded()
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations.removeValue(forKey: id) }
            }
        }
    }

    public func send(_ message: GameWireMessage, to peers: [OnlinePeer], reliably: Bool = true) async throws {
        try await send(ClientSocketEnvelope(type: .wire, recipients: peers.map(\.playerID), reliable: reliably, message: message))
    }

    public func sendToAll(_ message: GameWireMessage, reliably: Bool = true) async throws {
        try await send(ClientSocketEnvelope(type: .wire, recipients: nil, reliable: reliably, message: message))
    }

    public func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    private func connectIfNeeded() {
        guard socketTask == nil else { return }
        let task = session.webSocketTask(with: socketURL)
        socketTask = task
        task.resume()
        receiveTask = Task { [weak self, weak task] in
            guard let self, let task else { return }
            await self.receiveLoop(task: task)
        }
    }

    private func receiveLoop(task: URLSessionWebSocketTask) async {
        do {
            while !Task.isCancelled {
                let message = try await task.receive()
                try handleSocketMessage(message)
            }
        } catch {
            if !Task.isCancelled {
                lastError = error.localizedDescription
            }
        }
    }

    private func send(_ envelope: ClientSocketEnvelope) async throws {
        connectIfNeeded()
        guard let socketTask else {
            throw CloudflareRoomTransportError.socketNotConnected
        }
        let data = try encoder.encode(envelope)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CloudflareRoomTransportError.invalidSocketMessage
        }
        try await socketTask.send(.string(text))
    }

    private func handleSocketMessage(_ message: URLSessionWebSocketTask.Message) throws {
        let data: Data
        switch message {
        case let .data(payload):
            data = payload
        case let .string(text):
            guard let payload = text.data(using: .utf8) else {
                throw CloudflareRoomTransportError.invalidSocketMessage
            }
            data = payload
        @unknown default:
            throw CloudflareRoomTransportError.invalidSocketMessage
        }

        let envelope = try decoder.decode(ServerSocketEnvelope.self, from: data)
        switch envelope.type {
        case .room, .presence:
            if let room = envelope.room {
                participants = room.peers
                hostPlayerID = room.hostPlayerID
            }
        case .wire:
            guard let sender = envelope.sender, let message = envelope.message else { return }
            for continuation in continuations.values {
                continuation.yield(ReceivedRoomMessage(message: message, sender: sender))
            }
        case .error:
            lastError = envelope.error
        case .pong:
            break
        }
    }

    private static func postRoomRequest<Request: Encodable>(
        _ body: Request,
        to url: URL,
        session: URLSession
    ) async throws -> CloudflareRoomSummary {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try PreferansJSONCoder.encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CloudflareRoomTransportError.invalidHTTPResponse
        }
        if !(200..<300).contains(http.statusCode) {
            if let error = try? PreferansJSONCoder.decoder.decode(RoomServerError.self, from: data) {
                throw CloudflareRoomTransportError.serverError(error.error)
            }
            throw CloudflareRoomTransportError.serverError("Room server returned HTTP \(http.statusCode).")
        }
        return try PreferansJSONCoder.decoder.decode(CloudflareRoomSummary.self, from: data)
    }

    private static func endpoint(_ baseURL: URL, _ components: String...) -> URL {
        components.reduce(baseURL) { url, component in
            url.appendingPathComponent(component)
        }
    }
}

private struct CreateRoomRequest: Encodable {
    var localPeer: OnlinePeer
    var seats: [OnlinePeer]
    var maxPlayers: Int
}

private struct JoinRoomRequest: Encodable {
    var localPeer: OnlinePeer
}

private struct RoomServerError: Decodable {
    var error: String
    var code: String?
}

private struct ClientSocketEnvelope: Encodable {
    var type: SocketEnvelopeType
    var recipients: [PlayerID]?
    var reliable: Bool?
    var message: GameWireMessage?
}

private struct ServerSocketEnvelope: Decodable {
    var type: SocketEnvelopeType
    var room: CloudflareRoomSummary?
    var sender: OnlinePeer?
    var message: GameWireMessage?
    var error: String?
    var code: String?
    var serverSequence: Int?
    var sentAt: String?
}

private enum SocketEnvelopeType: String, Codable {
    case room
    case presence
    case wire
    case error
    case pong
}
