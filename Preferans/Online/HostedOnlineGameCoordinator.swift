#if canImport(GameKit)
import Foundation
import GameKit
import PreferansEngine

@MainActor
public final class HostedOnlineGameCoordinator: ObservableObject {
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
    @Published public private(set) var isHost: Bool = false
    @Published public private(set) var localSeat: PlayerID?
    @Published public private(set) var tableID: UUID?
    @Published public var errorText: String?

    private var transport: GameKitRealtimeTransport?
    private var hostActor: HostGameActor?
    private var listenTask: Task<Void, Never>?
    private var hostPlayer: GKPlayer?
    private var playersBySeat: [PlayerID: GKPlayer] = [:]
    private var seats: [PlayerIdentity] = []
    private var rules: PreferansRules = .sochi
    private let cloudStore: CloudKitGameArchiveStore?

    public init(cloudStore: CloudKitGameArchiveStore? = defaultCloudStore()) {
        self.cloudStore = cloudStore
    }

    deinit {
        listenTask?.cancel()
    }

    public func attach(match: GKMatch, rules: PreferansRules = .sochi) async {
        self.rules = rules
        self.errorText = nil
        self.state = .selectingHost

        let transport = GameKitRealtimeTransport(match: match)
        self.transport = transport
        self.listenTask?.cancel()
        self.listenTask = listen(to: transport)

        let participants = orderedParticipants(for: match)
        let seats = participants.map { player in
            PlayerIdentity(
                playerID: PlayerID(player.gamePlayerID),
                gamePlayerID: player.gamePlayerID,
                displayName: player.displayName
            )
        }
        self.seats = seats
        self.playersBySeat = Dictionary(uniqueKeysWithValues: participants.map { (PlayerID($0.gamePlayerID), $0) })
        self.localSeat = PlayerID(GKLocalPlayer.local.gamePlayerID)

        let host = await chooseHost(for: match) ?? participants.first ?? GKLocalPlayer.local
        self.hostPlayer = host
        self.isHost = host.gamePlayerID == GKLocalPlayer.local.gamePlayerID

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
            guard let hostPlayer, let transport else {
                errorText = "No host connection."
                return
            }
            do {
                try transport.send(.clientAction(envelope), to: [hostPlayer], reliably: true)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    public func requestResync() {
        guard let tableID, let localSeat, let hostPlayer, let transport else { return }
        do {
            try transport.send(
                .resyncRequest(ResyncRequestEnvelope(tableID: tableID, requester: localSeat, lastSeenSequence: projection?.sequence ?? 0)),
                to: [hostPlayer],
                reliably: true
            )
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func becomeHost(host: GKPlayer, seats: [PlayerIdentity], rules: PreferansRules) async {
        let tableID = UUID()
        self.tableID = tableID
        do {
            let hostID = PlayerID(host.gamePlayerID)
            let actor = try HostGameActor(tableID: tableID, hostPlayerID: hostID, seats: seats, rules: rules)
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

    private func listen(to transport: GameKitRealtimeTransport) -> Task<Void, Never> {
        Task { [weak self] in
            guard let stream = self?.transport?.messages() else { return }
            for await received in stream {
                await self?.handle(received)
            }
        }
    }

    private func handle(_ received: ReceivedGameKitMessage) async {
        switch received.message {
        case let .seatAssignment(assignment):
            guard !isHost else { return }
            tableID = assignment.tableID
            rules = assignment.rules
            seats = assignment.seats
            hostPlayer = playersBySeat[assignment.hostPlayerID] ?? hostPlayer
            localSeat = PlayerID(GKLocalPlayer.local.gamePlayerID)
            state = .connectedAsClient
            requestResync()

        case let .hello(hello):
            guard isHost else { return }
            if tableID == nil { tableID = hello.tableID }
            if let hostActor, let player = playersBySeat[hello.player.playerID] {
                do {
                    let envelope = try await hostActor.fullResync(for: hello.player.playerID)
                    try transport?.send(.projection(envelope), to: [player], reliably: true)
                } catch {
                    sendHostError(to: player, recipient: hello.player.playerID, nonce: nil, message: error.localizedDescription)
                }
            }

        case let .clientAction(envelope):
            guard isHost else { return }
            let senderID = PlayerID(received.sender.gamePlayerID)
            await applyClientAction(envelope, sender: senderID) { error in
                sendHostError(
                    to: received.sender,
                    recipient: envelope.actor,
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
                } else if let player = playersBySeat[request.requester] {
                    try transport?.send(.projection(envelope), to: [player], reliably: true)
                }
            } catch {
                errorText = error.localizedDescription
            }

        case .ping:
            break
        }
    }

    /// Applies a client envelope through the host actor and surfaces the
    /// result. `sender` is the seat the envelope speaks for (used by the
    /// actor for spoof checks); `onError` decides what to do when the
    /// engine rejects the action — locally we set ``errorText``, for a
    /// remote sender we ship a ``HostErrorEnvelope`` back.
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

        guard let transport else { return }
        for (viewer, projection) in update.projections where viewer != localSeat {
            guard let player = playersBySeat[viewer] else { continue }
            do {
                let envelope = ProjectionEnvelope(
                    tableID: update.tableID,
                    sequence: update.sequence,
                    viewer: viewer,
                    projection: projection,
                    eventSummaries: update.eventSummaries
                )
                try transport.send(.projection(envelope), to: [player], reliably: true)
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

    private func sendHostError(to player: GKPlayer, recipient: PlayerID?, nonce: UUID?, message: String) {
        guard let tableID, let transport else { return }
        let error = HostErrorEnvelope(
            tableID: tableID,
            sequence: projection?.sequence ?? 0,
            recipient: recipient,
            clientNonce: nonce,
            message: message
        )
        do {
            try transport.send(.hostError(error), to: [player], reliably: true)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func orderedParticipants(for match: GKMatch) -> [GKPlayer] {
        var unique: [String: GKPlayer] = [GKLocalPlayer.local.gamePlayerID: GKLocalPlayer.local]
        for player in match.players {
            unique[player.gamePlayerID] = player
        }
        return unique.values.sorted { $0.gamePlayerID < $1.gamePlayerID }
    }

    private func chooseHost(for match: GKMatch) async -> GKPlayer? {
        await withCheckedContinuation { continuation in
            match.chooseBestHostingPlayer { player in
                continuation.resume(returning: player)
            }
        }
    }
}

public func defaultCloudStore() -> CloudKitGameArchiveStore? {
    #if canImport(CloudKit)
    guard AppIdentifiers.cloudKitContainer != "iCloud.com.example.preferans" else {
        return nil
    }
    return CloudKitGameArchiveStore()
    #else
    return nil
    #endif
}
#endif
