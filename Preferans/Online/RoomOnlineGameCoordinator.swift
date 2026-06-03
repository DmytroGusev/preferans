import Foundation
import OSLog
import PreferansEngine

private let onlineFlowLogger = Logger(subsystem: "com.mixandmatch.preferans", category: "online-flow")

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
        /// A host-driven bot.
        case bot
        /// A reserved seat nobody has joined yet (`pending:`).
        case openWaiting
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
    func send(_ message: GameWireMessage, to peers: [OnlinePeer], reliably: Bool) async throws
    func sendToAll(_ message: GameWireMessage, reliably: Bool) async throws
    /// Ask the room's authority to convert every still-open (`pending:`) seat into
    /// a host-driven bot. Returns the updated roster when the transport owns a
    /// server-side authority that performed the change (Cloudflare), or `nil` when
    /// the caller should fall back to converting seats locally (in-memory/GameKit).
    func fillPendingSeatsWithBots() async throws -> [OnlinePeer]?
    func disconnect()
}

public extension RoomRealtimeTransport {
    /// Default: no server-pushed presence, so the roster is fixed at attach time.
    func participantUpdates() -> AsyncStream<[OnlinePeer]> {
        AsyncStream { $0.finish() }
    }

    /// Default: no server-side seat authority — the caller converts seats itself.
    func fillPendingSeatsWithBots() async throws -> [OnlinePeer]? { nil }
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
    @Published public private(set) var liveness: OnlineLiveness = .connecting
    @Published public var errorText: String?
    /// Pre-deal seat occupancy for the online waiting room. Empty once a deal is
    /// underway (the live table reads the projection instead).
    @Published public private(set) var rosterSeats: [WaitingRoomSeat] = []
    /// True when every seat is filled by a human or a bot — i.e. the host may
    /// start the first deal. False while any `pending:` seat is still open.
    @Published public private(set) var canHostStart: Bool = false

    private var transport: (any RoomRealtimeTransport)?
    private var hostActor: HostGameActor?
    private var listenTask: Task<Void, Never>?
    private var participantsTask: Task<Void, Never>?
    private var hostPeer: OnlinePeer?
    private var peersBySeat: [PlayerID: OnlinePeer] = [:]
    private var seats: [PlayerIdentity] = []
    private var rules: PreferansRules = .sochi
    private let cloudStore: (any GameArchiveStore)?
    private let dealSource: DealSource
    private var didAutoStartOnlineDeal = false

    /// Seats this host drives as server-side bots (derived from `bot:` peers).
    private var botSeats: Set<PlayerID> = []
    /// Shared strategy for every bot seat — a value type, safe to reuse.
    private let botStrategy: any PlayerStrategy = HeuristicStrategy()
    /// Pacing for host-driven bot moves. Only the host runs the loop.
    private let botMoveDelay: Duration
    /// When false, this coordinator never runs the server-side bot loop. The
    /// in-memory demo/test room sets this off because it drives its bots through
    /// separate per-seat coordinators instead.
    private let runsServerSideBots: Bool
    private var pendingBotTask: Task<Void, Never>?

    private let heartbeat: HeartbeatConfig
    private var heartbeatTask: Task<Void, Never>?
    private var lastHostContact: ContinuousClock.Instant?
    private let livenessClock = ContinuousClock()

    public init(
        cloudStore: (any GameArchiveStore)? = nil,
        dealSource: DealSource = RandomDealSource(),
        heartbeat: HeartbeatConfig = .default,
        botMoveDelay: Duration = BotPacing.interactive,
        runsServerSideBots: Bool = true
    ) {
        self.cloudStore = cloudStore
        self.dealSource = dealSource
        self.heartbeat = heartbeat
        self.botMoveDelay = botMoveDelay
        self.runsServerSideBots = runsServerSideBots
    }

    deinit {
        listenTask?.cancel()
        participantsTask?.cancel()
        heartbeatTask?.cancel()
        pendingBotTask?.cancel()
    }

    public func attach(transport: any RoomRealtimeTransport, rules: PreferansRules = .sochi) async {
        self.rules = rules
        self.errorText = nil
        self.state = .selectingHost
        self.liveness = .connecting
        self.lastHostContact = nil
        self.didAutoStartOnlineDeal = false
        self.transport = transport
        self.listenTask?.cancel()
        self.participantsTask?.cancel()
        self.heartbeatTask?.cancel()
        self.listenTask = listen(to: transport)
        self.participantsTask = observeParticipants(of: transport)

        let participants = orderedParticipants(from: transport.participants)
        let seats = participants.map(\.playerIdentity)
        self.seats = seats
        self.peersBySeat = Dictionary(uniqueKeysWithValues: participants.map { ($0.playerID, $0) })
        self.botSeats = Set(participants.filter(\.isBotSeat).map(\.playerID))
        self.localSeat = transport.localPeer.playerID
        recomputeRoster()

        let host = await transport.chooseHost() ?? participants.first ?? transport.localPeer
        self.hostPeer = host
        self.isHost = host.playerID == transport.localPeer.playerID

        if isHost {
            await becomeHost(host: host, seats: seats, rules: rules)
        } else {
            self.state = .connectedAsClient
            await sendHello()
            startHeartbeat()
        }
    }

    public func detach() {
        listenTask?.cancel()
        listenTask = nil
        participantsTask?.cancel()
        participantsTask = nil
        stopHeartbeat()
        pendingBotTask?.cancel()
        pendingBotTask = nil
        transport?.disconnect()
        transport = nil
        hostActor = nil
        projection = nil
        eventLog = []
        recentEvents = []
        isHost = false
        localSeat = nil
        tableID = nil
        liveness = .connecting
        lastHostContact = nil
        didAutoStartOnlineDeal = false
        botSeats = []
        rosterSeats = []
        canHostStart = false
        state = .disconnected
    }

    public func send(_ action: PreferansAction) {
        guard let tableID, let localSeat else {
            errorText = "No active online table."
            return
        }
        refreshPeersFromTransport()
        // The envelope's `actor` is the seat the action speaks for. For
        // most actions this equals the local seat, but in single-whist
        // greedy play the lone whister sends play actions on behalf of
        // the passer — `action.actor` then names the passer while the
        // wire sender stays the whister. The host validates the sender
        // against the controlling actor for that seat.
        let envelope = ClientActionEnvelope(
            tableID: tableID,
            actor: action.actor ?? localSeat,
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
            Task { [weak self, hostPeer, transport] in
                do {
                    try await transport.send(.clientAction(envelope), to: [hostPeer], reliably: true)
                } catch {
                    self?.errorText = error.localizedDescription
                }
            }
        }
    }

    public func requestResync() {
        refreshPeersFromTransport()
        guard let tableID, let localSeat, let hostPeer, let transport else { return }
        let lastSeenSequence = projection?.sequence ?? 0
        Task { [weak self, tableID, localSeat, hostPeer, transport, lastSeenSequence] in
            do {
                try await transport.send(
                    .resyncRequest(ResyncRequestEnvelope(tableID: tableID, requester: localSeat, lastSeenSequence: lastSeenSequence)),
                    to: [hostPeer],
                    reliably: true
                )
            } catch {
                self?.errorText = error.localizedDescription
            }
        }
    }

    // MARK: - Waiting room / host start

    /// Host kicks off the first deal from the waiting room. The actual deck and
    /// dealer are filled in authoritatively by ``HostGameActor`` (`makeAuthoritative`).
    public func startFirstDeal() {
        guard isHost else { return }
        send(.startDeal(dealer: nil, deck: nil))
    }

    /// Convert every still-open (`pending:`) seat into a host-driven bot, then
    /// re-advertise the roster so clients see the change. Use this when a friend
    /// didn't show and the host wants to start anyway.
    ///
    /// When the transport owns a server-side authority (Cloudflare), the relay's
    /// Durable Object flips the seats and pushes the new roster over presence —
    /// closing the late-join race at the source, since a human can no longer be
    /// routed onto a seat the server already converted. Transports with no such
    /// authority (in-memory/GameKit) fall back to converting locally and
    /// advertising the roster over the wire.
    public func fillOpenSeatsWithBots() async {
        guard isHost else { return }
        do {
            if try await transport?.fillPendingSeatsWithBots() != nil {
                refreshPeersFromTransport()
                return
            }
        } catch {
            errorText = error.localizedDescription
            return
        }
        refreshPeersFromTransport()
        var changed = false
        for identity in seats {
            guard let peer = peersBySeat[identity.playerID], peer.isPendingSeat else { continue }
            peersBySeat[identity.playerID] = OnlinePeer(
                playerID: identity.playerID,
                accountID: "\(OnlinePeer.botAccountPrefix)\(identity.playerID.rawValue)",
                provider: .dev,
                displayName: identity.displayName
            )
            botSeats.insert(identity.playerID)
            changed = true
        }
        guard changed else { return }
        recomputeRoster()
        if let tableID, let localSeat {
            let assignment = SeatAssignmentEnvelope(
                tableID: tableID,
                hostPlayerID: localSeat,
                seats: seats,
                rules: rules
            )
            try? await transport?.sendToAll(.seatAssignment(assignment), reliably: true)
        }
    }

    /// Convenience for the waiting-room CTA: fill no-show seats with bots and
    /// immediately start.
    public func fillOpenSeatsWithBotsAndStart() async {
        await fillOpenSeatsWithBots()
        startFirstDeal()
    }

    /// Recompute the published `rosterSeats` / `canHostStart` from the current
    /// seat list + peer map. Cheap; called wherever the peer mapping changes.
    private func recomputeRoster() {
        let roster = seats.map { identity -> WaitingRoomSeat in
            let peer = peersBySeat[identity.playerID]
            let occupancy: WaitingRoomSeat.Occupancy
            if identity.playerID == localSeat {
                occupancy = .you(name: identity.displayName)
            } else if peer?.isBotSeat == true {
                occupancy = .bot
            } else if peer?.isPendingSeat == true {
                occupancy = .openWaiting
            } else {
                occupancy = .human(name: peer?.displayName ?? identity.displayName)
            }
            return WaitingRoomSeat(player: identity.playerID, occupancy: occupancy)
        }
        let canStart = !roster.isEmpty && roster.allSatisfy { seat in
            if case .openWaiting = seat.occupancy { return false }
            return true
        }
        if rosterSeats != roster { rosterSeats = roster }
        if canHostStart != canStart { canHostStart = canStart }
    }

    // MARK: - Server-side bots

    /// If a host-driven bot owes the current move, pace it off-actor and apply
    /// it. Re-armed after every `publish`, so it cascades a bot through the
    /// auction and trick play and then idles once a human (or no one) is on the
    /// clock. Mirrors the local `GameViewModel.scheduleBotIfNeeded` loop but
    /// keeps the engine inside the host actor.
    private func scheduleBotMoveIfNeeded() {
        pendingBotTask?.cancel()
        pendingBotTask = nil
        guard runsServerSideBots, isHost, let hostActor, let tableID, !botSeats.isEmpty else { return }
        let botSeats = self.botSeats
        let delay = botMoveDelay
        let strategy = botStrategy
        pendingBotTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let plan = await hostActor.nextBotDecisionPlan(botSeats: botSeats) else { return }
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            if Task.isCancelled { return }
            guard let action = await strategy.decide(snapshot: plan.snapshot, viewer: plan.decider),
                  !Task.isCancelled else { return }
            // A human action (or a prior bot move) may have advanced the engine
            // while we paced/decided — drop the now-stale move; the publish that
            // changed the state already re-armed the loop against the truth.
            guard await hostActor.stillAwaiting(plan.snapshot.state) else { return }
            let envelope = ClientActionEnvelope(
                tableID: tableID,
                actor: action.actor ?? plan.decider,
                action: action,
                baseHostSequence: plan.baseSequence
            )
            await self.applyClientAction(envelope, sender: plan.decider) { error in
                self.errorText = error.localizedDescription
            }
        }
    }

    // MARK: - Host liveness

    /// Clients probe the host on a fixed cadence and flag `.hostUnreachable`
    /// when no host message (projection, error, or ping echo) has arrived within
    /// `heartbeat.hostTimeout`. The host never runs this — it is the authority.
    private func startHeartbeat() {
        guard heartbeat.isEnabled, !isHost else { return }
        heartbeatTask?.cancel()
        lastHostContact = livenessClock.now
        let interval = heartbeat.interval
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled else { break }
                await self.heartbeatTick()
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    private func heartbeatTick() async {
        guard !isHost, let tableID, let hostPeer, let transport else { return }
        if let last = lastHostContact,
           last.duration(to: livenessClock.now) > heartbeat.hostTimeout,
           liveness != .hostUnreachable {
            liveness = .hostUnreachable
        }
        try? await transport.send(.ping(PingEnvelope(tableID: tableID)), to: [hostPeer], reliably: false)
    }

    /// Record that we just heard from the host and clear any stall flag. When
    /// this is a *recovery* — we had flagged the host unreachable and contact
    /// just resumed (a reconnect, or the host coming back) — pull a fresh
    /// projection so we catch up on anything missed while we were away.
    private func noteHostContact() {
        guard !isHost else { return }
        let wasUnreachable = liveness == .hostUnreachable
        lastHostContact = livenessClock.now
        if liveness != .live {
            liveness = .live
        }
        if wasUnreachable {
            requestResync()
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
            self.liveness = .live

            let assignment = SeatAssignmentEnvelope(tableID: tableID, hostPlayerID: hostID, seats: seats, rules: rules)
            try await transport?.sendToAll(.seatAssignment(assignment), reliably: true)

            let update = await actor.initialUpdate()
            await publish(update)
            await persistTableSummary(update)
        } catch {
            self.errorText = error.localizedDescription
            self.state = .disconnected
        }
    }

    private func sendHello() async {
        guard let localSeat, let identity = seats.first(where: { $0.playerID == localSeat }) else { return }
        let hello = GameWireMessage.hello(
            HelloEnvelope(
                tableID: tableID,
                player: identity,
                lastSeenSequence: projection?.sequence ?? 0
            )
        )
        do {
            if let hostPeer {
                try await transport?.send(hello, to: [hostPeer], reliably: true)
            } else {
                try await transport?.sendToAll(hello, reliably: true)
            }
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

    /// Reconcile the roster against every presence broadcast the relay pushes.
    /// Without this, a client only learns the membership it saw at its own join:
    /// a later peer's arrival updates the host and the new joiner, but already-
    /// connected clients froze on a stale roster. Driving off the relay's presence
    /// keeps the Durable Object the single source of truth for who is seated.
    private func observeParticipants(of transport: any RoomRealtimeTransport) -> Task<Void, Never> {
        Task { [weak self] in
            for await _ in transport.participantUpdates() {
                self?.refreshPeersFromTransport()
            }
        }
    }

    private func handle(_ received: ReceivedRoomMessage) async {
        switch received.message {
        case let .seatAssignment(assignment):
            guard !isHost else { return }
            noteHostContact()
            tableID = assignment.tableID
            rules = assignment.rules
            seats = assignment.seats
            hostPeer = peersBySeat[assignment.hostPlayerID] ?? hostPeer
            localSeat = transport?.localPeer.playerID
            state = .connectedAsClient
            recomputeRoster()
            requestResync()

        case let .hello(hello):
            guard isHost else { return }
            // No late-join bot-seat guard is needed: the relay's Durable Object now
            // converts open seats to bots authoritatively (see `fillOpenSeatsWithBots`),
            // so a human is always routed onto a still-open seat and can never send a
            // hello for a seat the host already drives as a bot.
            if tableID == nil { tableID = hello.tableID }
            refreshPeerMapping(peer: received.sender, identity: hello.player)
            if let hostActor, let peer = peersBySeat[hello.player.playerID] {
                do {
                    if let tableID, let localSeat {
                        let assignment = SeatAssignmentEnvelope(
                            tableID: tableID,
                            hostPlayerID: localSeat,
                            seats: seats,
                            rules: rules
                        )
                        try await transport?.send(.seatAssignment(assignment), to: [peer], reliably: true)
                    }
                    let envelope = try await hostActor.fullResync(for: hello.player.playerID)
                    try await transport?.send(.projection(envelope), to: [peer], reliably: true)
                    await autoStartOnlineDealIfNeeded(afterJoin: hello.player.playerID)
                } catch {
                    await sendHostError(to: peer, recipient: hello.player.playerID, nonce: nil, message: error.localizedDescription)
                }
            }

        case let .clientAction(envelope):
            guard isHost else { return }
            await applyClientAction(envelope, sender: received.sender.playerID) { error in
                await sendHostError(
                    to: received.sender,
                    recipient: received.sender.playerID,
                    nonce: envelope.clientNonce,
                    message: error.localizedDescription
                )
            }

        case let .projection(envelope):
            guard !isHost else { return }
            noteHostContact()
            guard envelope.viewer == localSeat else { return }
            tableID = envelope.tableID
            projection = envelope.projection
            logOnlineFlowProjection(envelope.projection, source: "receive")
            eventLog.append(contentsOf: envelope.eventSummaries)
            appendRecentEvents(envelope.events)
            state = .connectedAsClient

        case let .hostError(error):
            noteHostContact()
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
                    try await transport?.send(.projection(envelope), to: [peer], reliably: true)
                }
            } catch {
                errorText = error.localizedDescription
            }

        case let .ping(ping):
            if isHost {
                // A client's liveness probe — echo it back so the client knows
                // the host process is alive even when no projection is pending
                // (e.g. while waiting on a human player's turn).
                let table = tableID ?? ping.tableID
                try? await transport?.send(.ping(PingEnvelope(tableID: table)), to: [received.sender], reliably: false)
            } else if received.sender.playerID == hostPeer?.playerID {
                noteHostContact()
            }
        }
    }

    private func applyClientAction(
        _ envelope: ClientActionEnvelope,
        sender: PlayerID?,
        onError: (Error) async -> Void
    ) async {
        guard let hostActor else { return }
        do {
            let update = try await hostActor.applyClientAction(envelope, sender: sender)
            await publish(update)
            await persistAfter(update)
        } catch {
            await onError(error)
        }
    }

    private func publish(_ update: HostUpdate) async {
        tableID = update.tableID
        refreshPeersFromTransport()
        if let localSeat, let localProjection = update.projections[localSeat] {
            projection = localProjection
            logOnlineFlowProjection(localProjection, source: "publishLocal")
        }
        eventLog.append(contentsOf: update.eventSummaries)
        appendRecentEvents(update.events)

        // Re-arm the bot loop against the new state before fanning projections
        // out — bots act through the in-process engine, so they don't depend on
        // the transport being present.
        scheduleBotMoveIfNeeded()

        guard let transport else { return }
        for (viewer, projection) in update.projections where viewer != localSeat {
            // Bot seats have no socket — they never receive wire projections;
            // the host advances them through its own engine.
            guard let peer = peersBySeat[viewer], !peer.isBotSeat else { continue }
            do {
                let envelope = ProjectionEnvelope(
                    tableID: update.tableID,
                    sequence: update.sequence,
                    viewer: viewer,
                    projection: projection,
                    eventSummaries: update.eventSummaries,
                    events: update.events
                )
                try await transport.send(.projection(envelope), to: [peer], reliably: true)
                logOnlineFlow("event=sendProjection recipient=\(viewer.rawValue) sequence=\(projection.sequence) phase=\(phaseToken(projection.phase))")
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
            try await cloudStore.upsertTableSummary(summary, latestPublicProjection: projection)
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
                try await cloudStore.upsertTableSummary(summary, latestPublicProjection: localProjection)
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

    private func sendHostError(to peer: OnlinePeer, recipient: PlayerID?, nonce: UUID?, message: String) async {
        guard let tableID, let transport else { return }
        let error = HostErrorEnvelope(
            tableID: tableID,
            sequence: projection?.sequence ?? 0,
            recipient: recipient,
            clientNonce: nonce,
            message: message
        )
        do {
            try await transport.send(.hostError(error), to: [peer], reliably: true)
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

    private func refreshPeersFromTransport() {
        guard let transport else { return }
        for peer in transport.participants {
            let existing = peersBySeat[peer.playerID]
            if shouldReplacePeer(existing, with: peer) {
                peersBySeat[peer.playerID] = peer
            }
            // Adopt any seat the relay reports as a bot so the host engine drives
            // it. Insert-only: a seat never un-bots, so this can't drop a bot the
            // local-authority path inserted before the roster echoed back.
            if peer.isBotSeat { botSeats.insert(peer.playerID) }
        }
        recomputeRoster()
    }

    private func refreshPeerMapping(peer: OnlinePeer, identity: PlayerIdentity) {
        peersBySeat[peer.playerID] = peer
        peersBySeat[identity.playerID] = peer
        if let index = seats.firstIndex(where: { $0.playerID == identity.playerID }) {
            seats[index] = identity
        }
        recomputeRoster()
    }

    private func shouldReplacePeer(_ existing: OnlinePeer?, with candidate: OnlinePeer) -> Bool {
        guard let existing else { return true }
        if existing.isPendingSeat {
            return true
        }
        if candidate.isPendingSeat {
            return false
        }
        return true
    }

    private func autoStartOnlineDealIfNeeded(afterJoin joinedPlayer: PlayerID) async {
        guard ProcessInfo.processInfo.arguments.contains(UITestFlags.autoStartOnlineDealOnJoin),
              isHost,
              !didAutoStartOnlineDeal,
              joinedPlayer != localSeat,
              allExpectedOnlinePlayersConnected(),
              let tableID,
              let localSeat,
              projection?.legal.canStartDeal == true else {
            return
        }
        didAutoStartOnlineDeal = true
        let envelope = ClientActionEnvelope(
            tableID: tableID,
            actor: localSeat,
            action: .startDeal(dealer: nil, deck: nil),
            baseHostSequence: projection?.sequence ?? 0
        )
        await applyClientAction(envelope, sender: localSeat) { error in
            self.errorText = error.localizedDescription
        }
    }

    private func allExpectedOnlinePlayersConnected() -> Bool {
        seats.allSatisfy { identity in
            guard let peer = peersBySeat[identity.playerID] else { return false }
            // A seat counts as filled when a human has claimed it or a bot owns
            // it; only an unclaimed `pending:` seat is still missing a player.
            // (`bot:` accounts are non-`pending:`, so this covers them too.)
            return !peer.isPendingSeat
        }
    }

    private func logOnlineFlowProjection(_ projection: PlayerGameProjection, source: String) {
        logOnlineFlow(
            "event=projection source=\(source) local=\(localSeat?.rawValue ?? "unknown") viewer=\(projection.viewer.rawValue) sequence=\(projection.sequence) phase=\(phaseToken(projection.phase)) tableID=\(projection.tableID.uuidString)"
        )
    }

    private func logOnlineFlow(_ message: String) {
        if ProcessInfo.processInfo.arguments.contains(UITestFlags.onlineFlowLogging) {
            let line = "ONLINE_FLOW \(message)"
            print(line)
            onlineFlowLogger.notice("\(line, privacy: .public)")
        }
    }

    private func phaseToken(_ phase: ProjectedPhase) -> String {
        switch phase {
        case .waitingForDeal:
            return "waitingForDeal"
        case .bidding:
            return "bidding"
        case .awaitingDiscard:
            return "awaitingDiscard"
        case .awaitingContract:
            return "awaitingContract"
        case .awaitingWhist:
            return "awaitingWhist"
        case .awaitingDefenderMode:
            return "awaitingDefenderMode"
        case .playing:
            return "playing"
        case .dealFinished:
            return "dealFinished"
        case .gameOver:
            return "gameOver"
        }
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
