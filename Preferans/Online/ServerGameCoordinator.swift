import Foundation
import Combine
import PreferansEngine

/// Production multiplayer is a projection consumer with a durable command outbox.
/// It never constructs an engine or elects a game authority on the device.
@MainActor
public final class ServerGameCoordinator: OnlineGamePresenting {
    @Published public private(set) var projection: PlayerGameProjection?
    @Published public private(set) var pendingAdvance: PendingAdvance?
    @Published public private(set) var eventLog: [String] = []
    @Published public private(set) var recentEvents: [PreferansEvent] = []
    @Published public private(set) var botInsights: [BotDecisionExplanation] = []
    @Published public private(set) var isHost = false // lobby manager only
    @Published public private(set) var liveness: OnlineLiveness = .connecting
    @Published public private(set) var transportStatus: OnlineTransportStatus = .connecting
    @Published public private(set) var errorText: String?
    @Published public private(set) var rosterSeats: [WaitingRoomSeat] = []
    @Published public private(set) var canHostStart = false
    @Published public private(set) var hasDisconnectedHumanSeat = false
    @Published public private(set) var isSubmitting = false
    public private(set) var tableID: UUID?

    private var transport: (any RoomRealtimeTransport)?
    private var pending: ClientActionEnvelope?
    private let outbox: OnlineCommandOutbox
    private var subscriptions: [Task<Void, Never>] = []
    private var retry: Task<Void, Never>?
    private var hold: Task<Void, Never>?
    private var generation = UUID()
    private var latestReceiptSequence = -1
    private var didAutoStart = false

    public init(outbox: OnlineCommandOutbox? = nil) {
        self.outbox = outbox ?? OnlineCommandOutbox()
    }

    deinit { retry?.cancel(); hold?.cancel(); subscriptions.forEach { $0.cancel() } }

    public var displayProjection: PlayerGameProjection? { projection?.applyingAdvanceFreeze(pendingAdvance) }

    public func attach(transport: any RoomRealtimeTransport) async {
        detach()
        self.transport = transport
        tableID = transport.authoritativeTableID
        transportStatus = .connecting
        let attachment = generation
        if let tableID {
            do { pending = try outbox.load(table: tableID, account: transport.localPeer.accountID) }
            catch { errorText = "Could not recover the pending move: \(error.localizedDescription)" }
        }
        isSubmitting = pending != nil
        // Construct streams before spawning tasks: the transport may replay frames immediately.
        let messages = transport.messages()
        let connections = transport.connectionEvents()
        let participants = transport.participantUpdates()
        subscriptions.append(Task { [weak self] in
            for await received in messages {
                guard let self, self.generation == attachment else { return }
                self.receive(received)
            }
        })
        subscriptions.append(Task { [weak self] in
            for await event in connections {
                guard let self, self.generation == attachment else { return }
                self.connection(event)
            }
        })
        subscriptions.append(Task { [weak self] in
            for await _ in participants {
                guard let self, self.generation == attachment else { return }
                await self.refreshRoster()
            }
        })
        await refreshRoster()
    }

    public func detach() {
        generation = UUID()
        subscriptions.forEach { $0.cancel() }; subscriptions = []
        retry?.cancel(); retry = nil
        hold?.cancel(); hold = nil
        transport?.disconnect(); transport = nil
        projection = nil; pendingAdvance = nil; pending = nil
        recentEvents = []; eventLog = []; botInsights = []
        tableID = nil; isHost = false; isSubmitting = false
        rosterSeats = []; canHostStart = false; hasDisconnectedHumanSeat = false
        latestReceiptSequence = -1; didAutoStart = false
        errorText = nil; liveness = .connecting; transportStatus = .disconnected
    }

    public func send(_ action: PreferansAction) {
        guard !isSubmitting, transportStatus == .connected,
              let transport, let projection, let tableID,
              projection.sequence >= latestReceiptSequence else { return }
        let command = ClientActionEnvelope(tableID: tableID,
            actor: action.actor ?? transport.localPeer.playerID, action: action,
            baseHostSequence: projection.sequence)
        do { try outbox.store(command, account: transport.localPeer.accountID) }
        catch { errorText = "Could not save your move. Please try again."; return }
        pending = command; isSubmitting = true; canHostStart = false; errorText = nil
        scheduleRetry()
    }

    @discardableResult
    public func startFirstDeal() -> Bool {
        updateStartAvailability()
        guard canHostStart else { return false }
        send(.startDeal(dealer: nil, deck: nil))
        return isSubmitting
    }

    public func fillOpenSeatsWithBotsAndStart() async {
        guard isHost, let transport else { return }
        let attachment = generation
        do {
            _ = try await transport.fillPendingSeatsWithBots()
            guard generation == attachment else { return }
            await refreshRoster()
            _ = startFirstDeal()
        } catch { if generation == attachment { errorText = error.localizedDescription } }
    }

    private func refreshRoster() async {
        guard let transport else { return }
        let attachment = generation
        let manager = await transport.chooseHost()
        guard generation == attachment else { return }
        isHost = manager?.playerID == transport.localPeer.playerID
        rosterSeats = transport.participants.map { peer in
            let occupancy: WaitingRoomSeat.Occupancy
            if peer.isPendingSeat { occupancy = .openWaiting }
            else if peer.isBotSeat { occupancy = .bot(name: peer.displayName) }
            else if peer.playerID == transport.localPeer.playerID { occupancy = .you(name: peer.displayName) }
            else { occupancy = .human(name: peer.displayName) }
            return WaitingRoomSeat(player: peer.playerID, occupancy: occupancy)
        }
        hasDisconnectedHumanSeat = transport.participants.contains {
            !$0.isBotSeat && !$0.isPendingSeat && !transport.connectedPlayerIDs.contains($0.playerID)
        }
        updateStartAvailability()
        if canHostStart, !didAutoStart,
           ProcessInfo.processInfo.arguments.contains(UITestFlags.autoStartOnlineDealOnJoin) {
            didAutoStart = startFirstDeal()
        }
    }

    private func updateStartAvailability() {
        guard let transport else { canHostStart = false; return }
        canHostStart = isHost && !isSubmitting && transportStatus == .connected
            && !hasDisconnectedHumanSeat && !transport.participants.contains(where: \.isPendingSeat)
            && projection?.legal.canStartDeal == true
    }

    private func receive(_ received: ReceivedRoomMessage) {
        guard received.authority == .server, case let .projection(frame) = received.message,
              frame.schemaVersion == PreferansWireSchema.current,
              frame.tableID == tableID, frame.viewer == transport?.localPeer.playerID,
              frame.projection.tableID == frame.tableID, frame.projection.viewer == frame.viewer,
              frame.projection.sequence == frame.sequence,
              frame.sequence >= (projection?.sequence ?? -1) else { return }
        transportStatus = .connected; liveness = .live
        let newer = frame.sequence > (projection?.sequence ?? -1)
        if newer {
            if let previous = projection, let freeze = AdvancePresentation.completedTrickHold(
                events: frame.events, viewer: frame.viewer, preProjection: previous,
                visibleTalonBeforeAction: previous.talon) {
                pendingAdvance = freeze
                hold?.cancel()
                hold = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(2_400))
                    guard !Task.isCancelled else { return }
                    self?.pendingAdvance = nil
                }
            }
            projection = frame.projection
            recentEvents = Array((recentEvents + frame.events).suffix(100))
            eventLog = Array((eventLog + frame.eventSummaries).suffix(100))
            botInsights = frame.botInsights
        } else if frame.sequence == 0 {
            // Lobby roster changes may rebuild the initial projection.
            projection = frame.projection
        }
        if ProcessInfo.processInfo.arguments.contains(UITestFlags.onlineFlowLogging) {
            print("ONLINE_FLOW event=projection source=receive local=\(frame.viewer.rawValue) viewer=\(frame.viewer.rawValue) sequence=\(frame.sequence) phase=\(frame.projection.phase.token)")
        }
        Task { [weak self] in await self?.refreshRoster() }
    }

    private func connection(_ event: RoomTransportEvent) {
        switch event {
        case .connected:
            transportStatus = .connected; liveness = .live
            scheduleRetry()
        case .reconnecting:
            transportStatus = .reconnecting; retry?.cancel(); retry = nil
        case .seatTakenOver:
            transportStatus = .seatTakenOver; retry?.cancel(); retry = nil
            canHostStart = false
        case let .serverError(message): errorText = message
        case let .commandReceipt(receipt):
            guard let pending, receipt.tableID == tableID, receipt.clientNonce == pending.clientNonce,
                  let transport else { return }
            do { try outbox.remove(table: pending.tableID, account: transport.localPeer.accountID) }
            catch { errorText = "Your move was resolved, but local recovery storage could not be cleared."; return }
            latestReceiptSequence = max(latestReceiptSequence, receipt.sequence)
            self.pending = nil; isSubmitting = false; retry?.cancel(); retry = nil
            errorText = receipt.status == .rejected ? (receipt.message ?? "The move was rejected.") : nil
        }
        Task { [weak self] in await self?.refreshRoster() }
    }

    private func scheduleRetry() {
        retry?.cancel()
        guard pending != nil, transportStatus == .connected else { return }
        let attachment = generation
        retry = Task { [weak self] in
            var attempt = 0
            while !Task.isCancelled {
                guard let self, self.generation == attachment,
                      let pending = self.pending, let transport = self.transport else { return }
                do { try await transport.sendToAll(.clientAction(pending), reliably: true) }
                catch { if self.generation == attachment { self.errorText = "Reconnecting… Your move is saved." } }
                attempt += 1
                try? await Task.sleep(for: .seconds(min(attempt * 2, 8)))
            }
        }
    }
}
