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
    /// Returned only in the `/create` response — the secret the room's host must
    /// present to perform host-only mutations (e.g. filling open seats with bots).
    /// Absent (`nil`) on join/summary/presence payloads, so guests never see it.
    public var hostSecret: String?
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
    /// The host secret from the `/create` response; required to authenticate
    /// host-only mutations. `nil` on a joined (guest) transport.
    private let hostSecret: String?
    private var socketTask: URLSessionWebSocketTask?
    private var connectionTask: Task<Void, Never>?
    private var isClosed = false
    private var continuations: [UUID: AsyncStream<ReceivedRoomMessage>.Continuation] = [:]
    private var participantContinuations: [UUID: AsyncStream<[OnlinePeer]>.Continuation] = [:]

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
        self.hostSecret = summary.hostSecret
        self.session = session
    }

    deinit {
        connectionTask?.cancel()
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
        // The server binds joiners to a seat by `accountID`: it honors the seat
        // we asked for when it's still open, but redirects us to another open
        // seat if ours was taken. Adopt the seat it actually gave us so
        // `localPeer`, `localSeat`, and the socket identity in
        // `summary.websocketURL` all agree.
        let assignedPeer = summary.peers.first { $0.accountID == localPeer.accountID } ?? localPeer
        return try CloudflareRoomTransport(baseURL: baseURL, summary: summary, localPeer: assignedPeer, session: session)
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

    public func participantUpdates() -> AsyncStream<[OnlinePeer]> {
        connectIfNeeded()
        let id = UUID()
        return AsyncStream { continuation in
            // Replay the current roster on subscribe so a presence frame that
            // landed between attach and this subscription isn't missed.
            continuation.yield(participants)
            participantContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.participantContinuations.removeValue(forKey: id) }
            }
        }
    }

    public func send(_ message: GameWireMessage, to peers: [OnlinePeer], reliably: Bool = true) async throws {
        try await send(ClientSocketEnvelope(type: .wire, recipients: peers.map(\.playerID), reliable: reliably, message: message))
    }

    public func sendToAll(_ message: GameWireMessage, reliably: Bool = true) async throws {
        try await send(ClientSocketEnvelope(type: .wire, recipients: nil, reliable: reliably, message: message))
    }

    /// Ask the worker to convert every still-open (`pending:`) seat into a bot.
    /// Authenticated with the host secret from `/create`, so only the host can do
    /// it. Adopts and re-publishes the roster the server returns so the caller
    /// sees the change without waiting for the presence broadcast to round-trip.
    public func fillPendingSeatsWithBots() async throws -> [OnlinePeer]? {
        guard let hostSecret else {
            throw CloudflareRoomTransportError.serverError("Only the host can fill open seats with bots.")
        }
        let summary = try await Self.postRoomRequest(
            FillBotsRequest(hostSecret: hostSecret),
            to: Self.endpoint(baseURL, "rooms", roomCode, "seats", "fill-bots"),
            session: session
        )
        participants = summary.peers
        hostPlayerID = summary.hostPlayerID
        emitParticipants()
        return summary.peers
    }

    /// Push the host's progress to the worker: lifecycle status, the
    /// worker-readable summary, and the opaque resume snapshot. Authenticated
    /// with the host secret, so a guest transport (no secret) is a silent no-op.
    /// Best-effort and called after every host update — the room/engine remain
    /// the source of truth if a report is lost.
    public func reportState(
        status: PreferansGameStatus,
        summary: OnlineStateSummary,
        snapshot: PreferansSnapshot?,
        snapshotSequence: Int
    ) async throws {
        guard let hostSecret else { return }
        // Send the snapshot as a *pre-encoded JSON string*, not an inline object:
        // the worker stores the blob via JS `JSON.parse`/`stringify`, which would
        // silently round large engine integers through a double and corrupt them
        // (> 2^53). Keeping it an opaque string makes the round-trip byte-exact.
        let snapshotBlob = try snapshot.map { String(decoding: try encoder.encode($0), as: UTF8.self) }
        let body = StateReportRequest(
            hostSecret: hostSecret,
            status: status,
            summary: summary,
            snapshot: snapshotBlob,
            snapshotSequence: snapshotSequence
        )
        var request = URLRequest(url: Self.endpoint(baseURL, "rooms", roomCode, "state"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CloudflareRoomTransportError.invalidHTTPResponse
        }
        if !(200..<300).contains(http.statusCode) {
            if let serverError = try? decoder.decode(RoomServerError.self, from: data) {
                throw CloudflareRoomTransportError.serverError(serverError.error)
            }
            throw CloudflareRoomTransportError.serverError("Room server returned HTTP \(http.statusCode).")
        }
    }

    /// Fetch the durable resume snapshot for a room, gated server-side on the
    /// caller presenting a seat they hold. Static because resume runs before a
    /// live transport exists — the lobby calls this, then hands the snapshot to
    /// a freshly attached coordinator.
    public static func fetchSnapshot(
        baseURL: URL = AppIdentifiers.roomWorkerBaseURL,
        roomCode: String,
        playerID: PlayerID,
        session: URLSession = .shared
    ) async throws -> ResumeSnapshotPayload {
        var components = URLComponents(
            url: endpoint(baseURL, "rooms", roomCode, "snapshot"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "playerID", value: playerID.rawValue)]
        guard let url = components?.url else {
            throw CloudflareRoomTransportError.invalidHTTPResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CloudflareRoomTransportError.invalidHTTPResponse
        }
        if !(200..<300).contains(http.statusCode) {
            if let serverError = try? PreferansJSONCoder.decoder.decode(RoomServerError.self, from: data) {
                throw CloudflareRoomTransportError.serverError(serverError.error)
            }
            throw CloudflareRoomTransportError.serverError("Room server returned HTTP \(http.statusCode).")
        }
        return try PreferansJSONCoder.decoder.decode(ResumeSnapshotPayload.self, from: data)
    }

    /// Abandon an unfinished game from the lobby (a game the player isn't
    /// currently sitting at). Authorized by the seat the account holds, not the
    /// host secret — so it works even though the original host is gone. Static,
    /// since there's no live transport for a game that isn't open.
    public static func abandon(
        baseURL: URL = AppIdentifiers.roomWorkerBaseURL,
        roomCode: String,
        playerID: PlayerID,
        session: URLSession = .shared
    ) async throws {
        var request = URLRequest(url: endpoint(baseURL, "rooms", roomCode, "abandon"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try PreferansJSONCoder.encoder.encode(AbandonRequest(playerID: playerID))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CloudflareRoomTransportError.invalidHTTPResponse
        }
        if !(200..<300).contains(http.statusCode) {
            if let serverError = try? PreferansJSONCoder.decoder.decode(RoomServerError.self, from: data) {
                throw CloudflareRoomTransportError.serverError(serverError.error)
            }
            throw CloudflareRoomTransportError.serverError("Room server returned HTTP \(http.statusCode).")
        }
    }

    private func emitParticipants() {
        for continuation in participantContinuations.values {
            continuation.yield(participants)
        }
    }

    public func disconnect() {
        isClosed = true
        connectionTask?.cancel()
        connectionTask = nil
        socketTask?.cancel(with: .goingAway, reason: nil)
        socketTask = nil
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
        for continuation in participantContinuations.values {
            continuation.finish()
        }
        participantContinuations.removeAll()
    }

    private func connectIfNeeded() {
        guard connectionTask == nil, !isClosed else { return }
        // Open the first socket *synchronously* so an immediately-following
        // `send` (the hello / seat assignment) sees a live `socketTask` rather
        // than racing the connection task onto the actor.
        let initial = openSocket()
        connectionTask = Task { [weak self] in
            await self?.maintainConnection(initial: initial)
        }
    }

    private func openSocket() -> URLSessionWebSocketTask {
        let task = session.webSocketTask(with: socketURL)
        socketTask = task
        task.resume()
        return task
    }

    /// Keeps a live WebSocket to the room relay, reconnecting with capped
    /// exponential backoff after any drop — instead of the old behavior where
    /// the first socket error silently killed the connection for good. A
    /// transient network blip now self-heals: the socket re-opens, the
    /// coordinator's heartbeat resumes, and host contact is re-established
    /// without the player having to leave and re-join the table.
    private func maintainConnection(initial: URLSessionWebSocketTask) async {
        var task = initial
        var attempt = 0
        while !Task.isCancelled, !isClosed {
            do {
                var establishedThisSocket = false
                while !Task.isCancelled {
                    let message = try await task.receive()
                    if !establishedThisSocket {
                        establishedThisSocket = true
                        attempt = 0            // a delivered frame proves the link is healthy
                        lastError = nil
                    }
                    try handleSocketMessage(message)
                }
            } catch {
                if Task.isCancelled || isClosed { break }
                lastError = error.localizedDescription
            }
            socketTask?.cancel()
            socketTask = nil
            if Task.isCancelled || isClosed { break }
            attempt += 1
            try? await Task.sleep(for: Self.reconnectDelay(attempt: attempt))
            if Task.isCancelled || isClosed { break }
            task = openSocket()
        }
        socketTask = nil
    }

    /// 0.5s, 1s, 2s, 4s, 8s (capped), each with up to +30% jitter so a fleet of
    /// clients dropped by the same outage don't reconnect in lockstep.
    private static func reconnectDelay(attempt: Int) -> Duration {
        let capped = min(pow(2.0, Double(attempt - 1)) * 0.5, 8.0)
        let jitter = Double.random(in: 0...0.3) * capped
        return .milliseconds(Int((capped + jitter) * 1000))
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
                emitParticipants()
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

private struct FillBotsRequest: Encodable {
    var hostSecret: String
}

private struct StateReportRequest: Encodable {
    var hostSecret: String
    var status: PreferansGameStatus
    var summary: OnlineStateSummary
    /// The PreferansSnapshot pre-encoded to a JSON string. Sent as a string (not
    /// a nested object) so the worker never re-parses it and can't lose integer
    /// precision; it stores and returns the bytes verbatim.
    var snapshot: String?
    var snapshotSequence: Int
}

private struct AbandonRequest: Encodable {
    var playerID: PlayerID
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
