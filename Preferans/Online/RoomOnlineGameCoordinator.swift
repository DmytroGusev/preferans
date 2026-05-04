import Foundation
import PreferansEngine

public enum OnlineAccountProvider: String, Codable, Sendable, Equatable {
    case gameCenter
    case apple
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

public struct ReceivedRoomMessage: Sendable {
    public var message: GameWireMessage
    public var sender: OnlinePeer

    public init(message: GameWireMessage, sender: OnlinePeer) {
        self.message = message
        self.sender = sender
    }
}

@MainActor
public protocol RoomRealtimeTransport: AnyObject {
    var localPeer: OnlinePeer { get }
    var participants: [OnlinePeer] { get }

    func chooseHost() async -> OnlinePeer?
    func messages() -> AsyncStream<ReceivedRoomMessage>
    func send(_ message: GameWireMessage, to peers: [OnlinePeer], reliably: Bool) throws
    func sendToAll(_ message: GameWireMessage, reliably: Bool) throws
    func disconnect()
}

@MainActor
public final class RoomOnlineGameCoordinator: ObservableObject {
    public enum ConnectionState: Equatable {
        case idle
        case selectingHost
        case connectedAsHost
        case connectedAsClient
        case disconnected
    }

    @Published public private(set) var state: ConnectionState = .idle
    @Published public private(set) var projection: PlayerGameProjection?
    @Published public private(set) var eventLog: [String] = []
    @Published public private(set) var recentEvents: [PreferansEvent] = []
    @Published public private(set) var isHost: Bool = false
    @Published public private(set) var localSeat: PlayerID?
    @Published public private(set) var tableID: UUID?
    @Published public var errorText: String?

    private var transport: (any RoomRealtimeTransport)?
    private var hostActor: HostGameActor?
    private var listenTask: Task<Void, Never>?
    private var hostPeer: OnlinePeer?
    private var peersBySeat: [PlayerID: OnlinePeer] = [:]
    private var seats: [PlayerIdentity] = []
    private var rules: PreferansRules = .sochi
    private let cloudStore: CloudKitGameArchiveStore?
    private let dealSource: DealSource

    public init(
        cloudStore: CloudKitGameArchiveStore? = nil,
        dealSource: DealSource = RandomDealSource()
    ) {
        self.cloudStore = cloudStore
        self.dealSource = dealSource
    }

    deinit {
        listenTask?.cancel()
    }

    public func attach(transport: any RoomRealtimeTransport, rules: PreferansRules = .sochi) async {
        self.rules = rules
        self.errorText = nil
        self.state = .selectingHost
        self.transport = transport
        self.listenTask?.cancel()
        self.listenTask = listen(to: transport)

        let participants = orderedParticipants(from: transport.participants)
        let seats = participants.map(\.playerIdentity)
        self.seats = seats
        self.peersBySeat = Dictionary(uniqueKeysWithValues: participants.map { ($0.playerID, $0) })
        self.localSeat = transport.localPeer.playerID

        let host = await transport.chooseHost() ?? participants.first ?? transport.localPeer
        self.hostPeer = host
        self.isHost = host.playerID == transport.localPeer.playerID

        if isHost {
            await becomeHost(host: host, seats: seats, rules: rules)
        } else {
            self.state = .connectedAsClient
            sendHello()
        }
    }

    public func detach() {
        listenTask?.cancel()
        listenTask = nil
        transport?.disconnect()
        transport = nil
        hostActor = nil
        projection = nil
        eventLog = []
        recentEvents = []
        isHost = false
        localSeat = nil
        tableID = nil
        state = .disconnected
    }

    public func send(_ action: PreferansAction) {
        guard let tableID, let localSeat else {
            errorText = "No active online table."
            return
        }
        let envelope = ClientActionEnvelope(
            tableID: tableID,
            actor: localSeat,
            action: action,
            baseHostSequence: projection?.sequence ?? 0
        )
        if isHost {
            Task { [localSeat] in
                await applyClientAction(envelope, sender: localSeat) { error in
                    self.errorText = error.localizedDescription
                }
            }
        } else {
            guard let hostPeer, let transport else {
                errorText = "No host connection."
                return
            }
            do {
                try transport.send(.clientAction(envelope), to: [hostPeer], reliably: true)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    public func requestResync() {
        guard let tableID, let localSeat, let hostPeer, let transport else { return }
        do {
            try transport.send(
                .resyncRequest(ResyncRequestEnvelope(tableID: tableID, requester: localSeat, lastSeenSequence: projection?.sequence ?? 0)),
                to: [hostPeer],
                reliably: true
            )
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func becomeHost(host: OnlinePeer, seats: [PlayerIdentity], rules: PreferansRules) async {
        let tableID = UUID()
        self.tableID = tableID
        do {
            let hostID = host.playerID
            let actor = try HostGameActor(
                tableID: tableID,
                hostPlayerID: hostID,
                seats: seats,
                rules: rules,
                dealSource: dealSource
            )
            self.hostActor = actor
            self.state = .connectedAsHost

            let assignment = SeatAssignmentEnvelope(tableID: tableID, hostPlayerID: hostID, seats: seats, rules: rules)
            try transport?.sendToAll(.seatAssignment(assignment), reliably: true)

            let update = await actor.initialUpdate()
            await publish(update)
            await persistTableSummary(update)
        } catch {
            self.errorText = error.localizedDescription
            self.state = .disconnected
        }
    }

    private func sendHello() {
        guard let localSeat, let identity = seats.first(where: { $0.playerID == localSeat }) else { return }
        do {
            try transport?.sendToAll(.hello(HelloEnvelope(tableID: tableID, player: identity, lastSeenSequence: projection?.sequence ?? 0)), reliably: true)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func listen(to transport: any RoomRealtimeTransport) -> Task<Void, Never> {
        Task { [weak self] in
            let stream = transport.messages()
            for await received in stream {
                await self?.handle(received)
            }
        }
    }

    private func handle(_ received: ReceivedRoomMessage) async {
        switch received.message {
        case let .seatAssignment(assignment):
            guard !isHost else { return }
            tableID = assignment.tableID
            rules = assignment.rules
            seats = assignment.seats
            hostPeer = peersBySeat[assignment.hostPlayerID] ?? hostPeer
            localSeat = transport?.localPeer.playerID
            state = .connectedAsClient
            requestResync()

        case let .hello(hello):
            guard isHost else { return }
            if tableID == nil { tableID = hello.tableID }
            if let hostActor, let peer = peersBySeat[hello.player.playerID] {
                do {
                    let envelope = try await hostActor.fullResync(for: hello.player.playerID)
                    try transport?.send(.projection(envelope), to: [peer], reliably: true)
                } catch {
                    sendHostError(to: peer, recipient: hello.player.playerID, nonce: nil, message: error.localizedDescription)
                }
            }

        case let .clientAction(envelope):
            guard isHost else { return }
            await applyClientAction(envelope, sender: received.sender.playerID) { error in
                sendHostError(
                    to: received.sender,
                    recipient: received.sender.playerID,
                    nonce: envelope.clientNonce,
                    message: error.localizedDescription
                )
            }

        case let .projection(envelope):
            guard !isHost else { return }
            guard envelope.viewer == localSeat else { return }
            tableID = envelope.tableID
            projection = envelope.projection
            eventLog.append(contentsOf: envelope.eventSummaries)
            appendRecentEvents(envelope.events)
            state = .connectedAsClient

        case let .hostError(error):
            if error.recipient == nil || error.recipient == localSeat {
                errorText = error.message
            }

        case let .resyncRequest(request):
            guard isHost, let hostActor else { return }
            guard request.tableID == tableID else { return }
            do {
                let envelope = try await hostActor.fullResync(for: request.requester)
                if request.requester == localSeat {
                    projection = envelope.projection
                } else if let peer = peersBySeat[request.requester] {
                    try transport?.send(.projection(envelope), to: [peer], reliably: true)
                }
            } catch {
                errorText = error.localizedDescription
            }

        case .ping:
            break
        }
    }

    private func applyClientAction(
        _ envelope: ClientActionEnvelope,
        sender: PlayerID?,
        onError: (Error) -> Void
    ) async {
        guard let hostActor else { return }
        do {
            let update = try await hostActor.applyClientAction(envelope, sender: sender)
            await publish(update)
            await persistAfter(update)
        } catch {
            onError(error)
        }
    }

    private func publish(_ update: HostUpdate) async {
        tableID = update.tableID
        if let localSeat, let localProjection = update.projections[localSeat] {
            projection = localProjection
        }
        eventLog.append(contentsOf: update.eventSummaries)
        appendRecentEvents(update.events)

        guard let transport else { return }
        for (viewer, projection) in update.projections where viewer != localSeat {
            guard let peer = peersBySeat[viewer] else { continue }
            do {
                let envelope = ProjectionEnvelope(
                    tableID: update.tableID,
                    sequence: update.sequence,
                    viewer: viewer,
                    projection: projection,
                    eventSummaries: update.eventSummaries,
                    events: update.events
                )
                try transport.send(.projection(envelope), to: [peer], reliably: true)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func persistTableSummary(_ update: HostUpdate) async {
        guard let cloudStore, let localSeat, let projection else { return }
        let summary = CloudTableSummary(
            tableID: update.tableID,
            status: update.status,
            hostPlayerID: localSeat,
            seats: seats,
            rules: rules,
            lastSequence: update.sequence
        )
        do {
            _ = try await cloudStore.saveTableSummary(summary, latestPublicProjection: projection)
        } catch {
            errorText = String(localized: "CloudKit table save failed: \(error.localizedDescription)")
        }
    }

    private func persistAfter(_ update: HostUpdate) async {
        guard let cloudStore else { return }
        do {
            if let action = update.validatedAction {
                try await cloudStore.appendValidatedAction(action)
            }
            try await cloudStore.saveHostSnapshot(update.snapshot, tableID: update.tableID, sequence: update.sequence)

            if let localProjection = projection, let localSeat {
                let summary = CloudTableSummary(
                    tableID: update.tableID,
                    status: update.status,
                    hostPlayerID: localSeat,
                    seats: seats,
                    rules: rules,
                    lastSequence: update.sequence
                )
                _ = try await cloudStore.saveTableSummary(summary, latestPublicProjection: localProjection)
            }

            if case let .dealFinished(result) = update.snapshot.state {
                try await cloudStore.saveCompletedDeal(
                    CompletedDealArchive(
                        tableID: update.tableID,
                        sequence: update.sequence,
                        result: result,
                        cumulativeScore: update.snapshot.score
                    )
                )
            }
        } catch {
            errorText = String(localized: "CloudKit archive failed: \(error.localizedDescription)")
        }
    }

    private func sendHostError(to peer: OnlinePeer, recipient: PlayerID?, nonce: UUID?, message: String) {
        guard let tableID, let transport else { return }
        let error = HostErrorEnvelope(
            tableID: tableID,
            sequence: projection?.sequence ?? 0,
            recipient: recipient,
            clientNonce: nonce,
            message: message
        )
        do {
            try transport.send(.hostError(error), to: [peer], reliably: true)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func appendRecentEvents(_ events: [PreferansEvent]) {
        guard !events.isEmpty else { return }
        recentEvents.append(contentsOf: events)
        if recentEvents.count > 120 {
            recentEvents.removeFirst(recentEvents.count - 120)
        }
    }

    private func orderedParticipants(from peers: [OnlinePeer]) -> [OnlinePeer] {
        peers.sorted { $0.playerID.rawValue < $1.playerID.rawValue }
    }
}

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

    public func send(_ message: GameWireMessage, to peers: [OnlinePeer], reliably: Bool = true) throws {
        guard !isDisconnected else { return }
        room.deliver(message, from: localPeer, to: peers)
    }

    public func sendToAll(_ message: GameWireMessage, reliably: Bool = true) throws {
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
