import Foundation
import OSLog
import PreferansEngine

private let onlineFlowLogger = Logger(subsystem: "com.mixandmatch.preferans", category: "online-flow")

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
    @Published public private(set) var pendingAdvance: PendingAdvance?
    @Published public private(set) var eventLog: [String] = []
    @Published public private(set) var recentEvents: [PreferansEvent] = []
    @Published public private(set) var isHost: Bool = false
    @Published public private(set) var localSeat: PlayerID?
    @Published public private(set) var tableID: UUID?
    @Published public private(set) var liveness: OnlineLiveness = .connecting
    @Published public private(set) var transportStatus: OnlineTransportStatus = .connecting
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
    private var transportEventsTask: Task<Void, Never>?
    private var hostRecoveryTask: Task<Void, Never>?
    private var durabilityRetryTask: Task<Void, Never>?
    private var durabilityBarrier: RoomDurabilityBarrier<HostUpdate>
    private var hostPeer: OnlinePeer?
    private var roster = RoomParticipantRoster()
    private var rules: PreferansRules = .sochi
    private var match: MatchSettings = .unbounded
    /// Variant label (`"odesa"`/`"wien"`) carried into the worker summary so the
    /// lobby's "Your games" rows can name the house rules. Presentation-only.
    private var variantTag: String?
    private let dealSource: DealSource
    private var didAutoStartOnlineDeal = false

    /// Shared strategy for every bot seat — a value type, safe to reuse.
    private let botStrategy: any PlayerStrategy = HeuristicStrategy()
    /// Pacing for host-driven bot moves. Only the host runs the loop.
    private let botMoveDelay: Duration
    /// Local presentation hold after a trick closes in online play. The host
    /// still publishes immediately; each client keeps the completed trick on
    /// screen briefly so humans can read who won before the next state appears.
    private let trickResultHoldDuration: Duration
    /// When false, this coordinator never runs the server-side bot loop. The
    /// in-memory demo/test room sets this off because it drives its bots through
    /// separate per-seat coordinators instead.
    private let runsServerSideBots: Bool
    private var pendingBotTask: Task<Void, Never>?
    private var pendingAdvanceTask: Task<Void, Never>?

    private let heartbeat: HeartbeatConfig
    private var heartbeatTask: Task<Void, Never>?
    private var lastHostContact: ContinuousClock.Instant?
    private let livenessClock = ContinuousClock()

    public init(
        dealSource: DealSource = RandomDealSource(),
        heartbeat: HeartbeatConfig = .default,
        botMoveDelay: Duration = BotPacing.interactive,
        trickResultHoldDuration: Duration = .milliseconds(1_400),
        durabilityRetryInitialDelay: Duration = .milliseconds(500),
        runsServerSideBots: Bool = true
    ) {
        self.dealSource = dealSource
        self.heartbeat = heartbeat
        self.botMoveDelay = botMoveDelay
        self.trickResultHoldDuration = trickResultHoldDuration
        self.durabilityBarrier = RoomDurabilityBarrier(
            initialRetryDelay: durabilityRetryInitialDelay
        )
        self.runsServerSideBots = runsServerSideBots
    }

    deinit {
        listenTask?.cancel()
        participantsTask?.cancel()
        transportEventsTask?.cancel()
        hostRecoveryTask?.cancel()
        durabilityRetryTask?.cancel()
        heartbeatTask?.cancel()
        pendingBotTask?.cancel()
        pendingAdvanceTask?.cancel()
    }

    public var displayProjection: PlayerGameProjection? {
        projection?.applyingAdvanceFreeze(pendingAdvance)
    }

    public func attach(
        transport: any RoomRealtimeTransport,
        rules: PreferansRules = .sochi,
        match: MatchSettings = .unbounded,
        variantTag: String? = nil,
        resume: OnlineResumeContext? = nil
    ) async {
        // On resume the snapshot's rules are authoritative — adopt them so the
        // seat assignment we broadcast matches the engine we rebuild.
        self.rules = resume?.snapshot.rules ?? rules
        self.match = resume?.snapshot.match ?? match
        self.variantTag = variantTag
        self.errorText = nil
        self.state = .selectingHost
        self.liveness = .connecting
        self.transportStatus = .connecting
        self.lastHostContact = nil
        self.didAutoStartOnlineDeal = false
        self.transport = transport
        self.listenTask?.cancel()
        self.participantsTask?.cancel()
        self.transportEventsTask?.cancel()
        self.hostRecoveryTask?.cancel()
        self.durabilityRetryTask?.cancel()
        self.durabilityBarrier.reset()
        self.heartbeatTask?.cancel()
        self.transportEventsTask = observeConnectionEvents(of: transport)
        self.listenTask = listen(to: transport)

        let participants = RoomParticipantRoster.ordered(transport.participants)
        self.roster = RoomParticipantRoster(participants: participants)
        self.localSeat = transport.localPeer.playerID
        recomputeRoster()

        let host = await transport.chooseHost() ?? participants.first ?? transport.localPeer
        self.hostPeer = host
        self.isHost = host.playerID == transport.localPeer.playerID

        if isHost {
            do {
                try await becomeHost(host: host, seats: roster.seats, rules: self.rules, match: self.match, resume: resume)
            } catch {
                beginHostRecovery(as: host, using: transport)
            }
        } else {
            self.state = .connectedAsClient
            await sendHello()
            startHeartbeat()
        }
        // Subscribe after the initial authority decision. The transport replays
        // its latest room state, so a migration that raced attach is still
        // observed without letting the replay compete with initial setup.
        self.participantsTask = observeParticipants(of: transport)
    }

    public func detach() {
        listenTask?.cancel()
        listenTask = nil
        participantsTask?.cancel()
        participantsTask = nil
        transportEventsTask?.cancel()
        transportEventsTask = nil
        hostRecoveryTask?.cancel()
        hostRecoveryTask = nil
        durabilityRetryTask?.cancel()
        durabilityRetryTask = nil
        durabilityBarrier.reset()
        stopHeartbeat()
        pendingBotTask?.cancel()
        pendingBotTask = nil
        pendingAdvanceTask?.cancel()
        pendingAdvanceTask = nil
        transport?.disconnect()
        transport = nil
        hostActor = nil
        projection = nil
        pendingAdvance = nil
        eventLog = []
        recentEvents = []
        isHost = false
        localSeat = nil
        tableID = nil
        liveness = .connecting
        transportStatus = .disconnected
        lastHostContact = nil
        didAutoStartOnlineDeal = false
        roster.reset()
        rosterSeats = []
        canHostStart = false
        state = .disconnected
    }

    public func send(_ action: PreferansAction) {
        guard transportStatus != .seatTakenOver else {
            errorText = String(localized: "This table is active on another device.")
            return
        }
        guard let tableID, let localSeat else {
            errorText = String(localized: "No active online table.")
            return
        }
        if case .startDeal = action, projection?.legal.canStartDeal != true {
            return
        }
        refreshPeersFromTransport()
        // The envelope's `actor` is the seat the action speaks for. For
        // most actions this equals the local seat, but in open single-whist
        // greedy play the lone whister sends play actions on behalf of the
        // passer's dummy hand — `action.actor` then names the passer while
        // the wire sender stays the whister. The host validates the sender
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
                errorText = String(localized: "No host connection.")
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
        guard isHost, transportStatus != .seatTakenOver else { return }
        refreshPeersFromTransport()
        guard allExpectedOnlinePlayersConnected() else {
            errorText = String(localized: "Start is available once every seat is filled — invite a friend or fill the empty seats with bots.")
            return
        }
        // Surface the not-ready case instead of falling into send(_:)'s
        // silent duplicate-startDeal guard: the waiting room disables its
        // Start button until an error or a deal arrives, so a silent no-op
        // would wedge the host behind a disabled button.
        guard projection?.legal.canStartDeal == true else {
            errorText = String(localized: "The table isn't ready to deal yet — try again in a moment.")
            return
        }
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
        guard isHost, transportStatus != .seatTakenOver else { return }
        do {
            if let peers = try await transport?.fillPendingSeatsWithBots() {
                adoptParticipantRoster(peers)
                await hostActor?.updateIdentities(roster.seats)
                return
            }
        } catch {
            errorText = error.localizedDescription
            return
        }
        refreshPeersFromTransport()
        guard roster.fillPendingSeatsWithBots() else { return }
        await hostActor?.updateIdentities(roster.seats)
        recomputeRoster()
        if let tableID, let localSeat {
            let assignment = SeatAssignmentEnvelope(
                tableID: tableID,
                hostPlayerID: localSeat,
                seats: roster.seats,
                rules: rules,
                match: match
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
        let seats = roster.waitingRoomSeats(localSeat: localSeat)
        if rosterSeats != seats { rosterSeats = seats }
        if canHostStart != roster.isReadyToStart { canHostStart = roster.isReadyToStart }
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
        guard runsServerSideBots, isHost, let hostActor, let tableID, !roster.botSeats.isEmpty else { return }
        let botSeats = roster.botSeats
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

    private func becomeHost(
        host: OnlinePeer,
        seats: [PlayerIdentity],
        rules: PreferansRules,
        match: MatchSettings,
        resume: OnlineResumeContext? = nil
    ) async throws {
        let tableID = UUID()
        self.tableID = tableID
        let hostID = host.playerID
        let actor: HostGameActor
        if let resume {
            // Rehydrate the engine from the durable snapshot the previous host
            // pushed to the worker, rather than starting a fresh deal.
            actor = try HostGameActor(
                tableID: tableID,
                hostPlayerID: hostID,
                seats: seats,
                resumeSnapshot: resume.snapshot,
                sequence: resume.sequence,
                dealSource: dealSource
            )
        } else {
            actor = try HostGameActor(
                tableID: tableID,
                hostPlayerID: hostID,
                seats: seats,
                rules: rules,
                match: match,
                dealSource: dealSource
            )
        }
        self.hostActor = actor

        // Establish durable truth before announcing this authority or exposing
        // its projection. Any client action built on a visible state must have
        // an already-recoverable snapshot behind it.
        let update = await actor.initialUpdate()
        try await reportStateToWorker(update)

        guard let transport else {
            throw CloudflareRoomTransportError.socketNotConnected
        }
        let assignment = SeatAssignmentEnvelope(
            tableID: tableID,
            hostPlayerID: hostID,
            seats: seats,
            rules: rules,
            match: match
        )
        try await transport.sendToAll(.seatAssignment(assignment), reliably: true)

        self.state = .connectedAsHost
        self.liveness = .live
        await publish(update)
    }

    private func sendHello() async {
        guard let localSeat, let identity = roster.identity(for: localSeat) else { return }
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
                guard let self else { return }
                self.refreshPeersFromTransport()
                await self.reconcileHostAuthority(using: transport)
            }
        }
    }

    private func observeConnectionEvents(of transport: any RoomRealtimeTransport) -> Task<Void, Never> {
        Task { [weak self] in
            for await event in transport.connectionEvents() {
                guard let self else { return }
                switch event {
                case .connected:
                    let recovered = self.transportStatus == .reconnecting
                    self.transportStatus = .connected
                    if recovered, !self.isHost {
                        self.requestResync()
                    }
                case .reconnecting:
                    self.transportStatus = .reconnecting
                case .seatTakenOver:
                    self.transportStatus = .seatTakenOver
                    self.stopHeartbeat()
                    self.pendingBotTask?.cancel()
                    self.pendingBotTask = nil
                }
            }
        }
    }

    /// Reconcile the coordinator with the Durable Object's current host. A
    /// presence frame can promote this seat, demote the previous host, or point
    /// a client at a new authority. Promotion always hydrates the worker's
    /// durable snapshot before the replacement emits any projection.
    private func reconcileHostAuthority(using transport: any RoomRealtimeTransport) async {
        guard self.transport === transport else { return }
        guard let elected = await transport.chooseHost() else { return }
        let previousHost = hostPeer?.playerID
        guard previousHost != elected.playerID else { return }

        hostPeer = elected
        if elected.playerID == transport.localPeer.playerID {
            beginHostRecovery(as: elected, using: transport)
        } else {
            becomeClient(of: elected)
        }
    }

    private func beginHostRecovery(as elected: OnlinePeer, using transport: any RoomRealtimeTransport) {
        hostRecoveryTask?.cancel()
        durabilityRetryTask?.cancel()
        durabilityRetryTask = nil
        durabilityBarrier.reset()
        stopHeartbeat()
        pendingBotTask?.cancel()
        pendingBotTask = nil
        hostActor = nil
        isHost = true
        state = .selectingHost
        liveness = .connecting
        errorText = nil

        hostRecoveryTask = Task { @MainActor [weak self, weak transport] in
            guard let self, let transport else { return }
            var delay: Duration = .milliseconds(250)
            while !Task.isCancelled {
                do {
                    let resume = try await transport.hostRecoveryContext()
                    guard !Task.isCancelled,
                          let current = await transport.chooseHost(),
                          current.playerID == transport.localPeer.playerID,
                          self.hostPeer?.playerID == current.playerID else { return }
                    if let resume {
                        self.rules = resume.snapshot.rules
                        self.match = resume.snapshot.match
                    }
                    try await self.becomeHost(
                        host: elected,
                        seats: self.roster.seats,
                        rules: self.rules,
                        match: self.match,
                        resume: resume
                    )
                    self.hostRecoveryTask = nil
                    return
                } catch {
                    self.errorText = String(
                        localized: "Recovering the table… Your game is safe."
                    )
                    try? await Task.sleep(for: delay)
                    delay = min(delay * 2, .seconds(4))
                }
            }
        }
    }

    private func becomeClient(of elected: OnlinePeer) {
        hostRecoveryTask?.cancel()
        hostRecoveryTask = nil
        durabilityRetryTask?.cancel()
        durabilityRetryTask = nil
        durabilityBarrier.reset()
        pendingBotTask?.cancel()
        pendingBotTask = nil
        hostActor = nil
        isHost = false
        hostPeer = elected
        state = .connectedAsClient
        liveness = .connecting
        lastHostContact = livenessClock.now
        errorText = nil
        Task { [weak self] in
            await self?.sendHello()
        }
        startHeartbeat()
    }

    /// True when a wire message came from the seat this client elected as host
    /// in the latest server presence (`hostPlayerID`). Seat assignments,
    /// projections, and host errors are only ever legitimate from that seat —
    /// the relay routes by recipient, not authority, so any seated peer could
    /// otherwise forge them (and a forged message must not count as host
    /// contact for liveness either).
    private func isFromHost(_ sender: OnlinePeer) -> Bool {
        sender.playerID == hostPeer?.playerID
    }

    private func handle(_ received: ReceivedRoomMessage) async {
        switch received.message {
        case let .seatAssignment(assignment):
            guard !isHost, isFromHost(received.sender) else { return }
            noteHostContact()
            let authorityChanged = tableID != assignment.tableID
            tableID = assignment.tableID
            if authorityChanged {
                // Never let controls from the previous authority remain live
                // under the replacement table ID. The incoming full projection
                // will repopulate the UI after snapshot recovery completes.
                projection = nil
                pendingAdvance = nil
                pendingAdvanceTask?.cancel()
                pendingAdvanceTask = nil
            }
            rules = assignment.rules
            match = assignment.match
            roster.replaceSeats(assignment.seats)
            hostPeer = roster.peer(for: assignment.hostPlayerID) ?? hostPeer
            localSeat = transport?.localPeer.playerID
            state = .connectedAsClient
            recomputeRoster()
            requestResync()

        case let .hello(hello):
            guard isHost else { return }
            if tableID == nil { tableID = hello.tableID }
            guard shouldAcceptHello(from: received.sender, identity: hello.player) else { return }
            await refreshPeerMapping(peer: received.sender, identity: hello.player)
            if let hostActor, let peer = roster.peer(for: hello.player.playerID) {
                do {
                    if let tableID, let localSeat {
                        let assignment = SeatAssignmentEnvelope(
                            tableID: tableID,
                            hostPlayerID: localSeat,
                            seats: roster.seats,
                            rules: rules,
                            match: match
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
            guard !isHost, isFromHost(received.sender) else { return }
            noteHostContact()
            guard envelope.viewer == localSeat else { return }
            // Projections can arrive out of order across a reconnect (a resync
            // response racing a newer live update). Within the same table the
            // sequence must never go backwards; a new table (rematch) starts a
            // fresh sequence and is always adopted.
            if envelope.tableID == tableID,
               let currentSequence = projection?.sequence,
               envelope.projection.sequence < currentSequence {
                return
            }
            tableID = envelope.tableID
            projection = envelope.projection
            beginTrickResultHoldIfNeeded(events: envelope.events, projection: envelope.projection)
            logOnlineFlowProjection(envelope.projection, source: "receive")
            eventLog.append(contentsOf: envelope.eventSummaries)
            appendRecentEvents(envelope.events)
            state = .connectedAsClient

        case let .hostError(error):
            // The host reports its own failures directly, so a wire host-error
            // is only ever legitimate on a client, from the host's seat.
            guard !isHost, isFromHost(received.sender) else { return }
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
                } else if let peer = roster.peer(for: request.requester) {
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
        guard durabilityBarrier.acceptsAction else {
            await onError(CloudflareRoomTransportError.serverError(
                String(localized: "Saving the previous move… Try again in a moment.")
            ))
            return
        }
        do {
            let update = try await hostActor.applyClientAction(envelope, sender: sender)
            do {
                try await reportStateToWorker(update)
            } catch {
                guard isHost else { return }
                queueDurabilityRetry(update, after: error)
                return
            }
            guard isHost, self.hostActor === hostActor else { return }
            await publish(update)
        } catch {
            await onError(error)
        }
    }

    private func queueDurabilityRetry(_ update: HostUpdate, after error: Error) {
        guard let ticket = durabilityBarrier.stage(update) else {
            assertionFailure("Durability barrier accepted two pending host updates")
            return
        }
        let message = String(localized: "Connection interrupted — saving your move…")
        errorText = message
        logOnlineFlow("event=reportStateRetry sequence=\(update.sequence) error=\(error.localizedDescription)")
        durabilityRetryTask?.cancel()
        durabilityRetryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let delay = self.durabilityBarrier.delay(for: ticket) else { return }
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled,
                      self.isHost,
                      let pending = self.durabilityBarrier.update(for: ticket) else { return }
                do {
                    try await self.reportStateToWorker(pending)
                    guard self.isHost,
                          self.durabilityBarrier.update(for: ticket) != nil else { return }
                    await self.publish(pending)
                    guard self.durabilityBarrier.complete(ticket) != nil else { return }
                    self.durabilityRetryTask = nil
                    if self.errorText == message {
                        self.errorText = nil
                    }
                    return
                } catch {
                    logOnlineFlow("event=reportStateRetryFailed sequence=\(pending.sequence) error=\(error.localizedDescription)")
                    guard self.durabilityBarrier.recordFailure(for: ticket) else { return }
                }
            }
        }
    }

    private func publish(_ update: HostUpdate) async {
        tableID = update.tableID
        refreshPeersFromTransport()
        if let localSeat, let localProjection = update.projections[localSeat] {
            projection = localProjection
            beginTrickResultHoldIfNeeded(events: update.events, projection: localProjection)
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
            guard let peer = roster.peer(for: viewer), !peer.isBotSeat else { continue }
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
                logOnlineFlow("event=sendProjection recipient=\(viewer.rawValue) sequence=\(projection.sequence) phase=\(projection.phase.token)")
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    /// Push the host's latest state into the worker so the durable game directory
    /// — and every participant's "Your games" list — stays current and the table
    /// stays resumable. Host-only, and only over the Cloudflare transport: the
    /// in-memory/GameKit transports have no worker behind them. For a real room
    /// this is a commit barrier: projections are not published until it passes.
    private func reportStateToWorker(_ update: HostUpdate) async throws {
        guard isHost, let transport, let hostActor else { return }
        let snapshot = await hostActor.engineSnapshot
        let summary = OnlineStateSummary(
            variant: variantTag,
            lastSequence: update.sequence,
            phase: Self.phaseLabel(for: update.snapshot.state),
            dealNumber: update.dealNumber,
            result: Self.finishedResult(from: update.snapshot.state)
        )
        try await transport.reportState(
            status: update.status,
            summary: summary,
            // A finished game is never resumed, so don't ship its snapshot.
            snapshot: update.status == .finished ? nil : snapshot,
            snapshotSequence: update.sequence
        )
    }

    /// Mark the current table abandoned in the worker directory so it drops out
    /// of the player's Continue list. Host-only and best-effort; a guest simply
    /// disconnects and the host's own reports continue to govern status.
    public func abandon() async {
        guard isHost, let cloud = transport as? CloudflareRoomTransport, let hostActor else { return }
        let sequence = await hostActor.currentSequence
        try? await cloud.reportState(
            status: .abandoned,
            summary: OnlineStateSummary(variant: variantTag, lastSequence: sequence),
            snapshot: nil,
            snapshotSequence: sequence
        )
    }

    /// Coarse, lobby-facing phase label for a deal state.
    private static func phaseLabel(for state: DealState) -> String {
        switch state {
        case .waitingForDeal:      return "waiting"
        case .bidding:             return "bidding"
        case .awaitingDiscard:     return "exchange"
        case .awaitingContract:    return "declaring"
        case .awaitingWhist:       return "whist"
        case .awaitingDefenderMode: return "defending"
        case .playing:             return "playing"
        case .dealFinished:        return "scoring"
        case .gameOver:            return "finished"
        }
    }

    /// Distill a finished match into the worker-readable result: the
    /// best-balance seat as winner plus each seat's final pool.
    private static func finishedResult(from state: DealState) -> OnlineGameResult? {
        guard case let .gameOver(summary) = state else { return nil }
        let winner = summary.standings.max(by: { $0.balance < $1.balance })?.player
        var finalScores: [String: Int] = [:]
        for standing in summary.standings {
            finalScores[standing.player.rawValue] = standing.pool
        }
        return OnlineGameResult(winner: winner, finalScores: finalScores)
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
        RecentActionFeed.append(events, to: &recentEvents)
    }

    /// Online counterpart of the local `GameViewModel.makePendingAdvance`
    /// tap-to-advance gate. The two hold policies are intentionally
    /// different — local play waits for the human's tap (with an idle hint),
    /// while online tables clear the hold on a timer so one distracted
    /// player can't stall three others — but both freeze the same
    /// `PendingAdvance` descriptor through `applyingAdvanceFreeze`. If you
    /// change what a hold freezes here, mirror it there.
    private func beginTrickResultHoldIfNeeded(events: [PreferansEvent], projection: PlayerGameProjection) {
        guard let trick = events.compactMap({ event -> Trick? in
            if case let .trickCompleted(trick) = event { return trick }
            return nil
        }).first else { return }

        let pending = PendingAdvance(
            waitingOn: localSeat ?? projection.viewer,
            trickPlays: trick.tablePlays,
            trickWinner: trick.winner,
            talonOverride: talonBeforeCompletedTrick(trick, projection: projection),
            phaseOverride: phaseOverrideForCompletedTrick(trick, in: projection),
            completedTrickCountOverride: max(0, projection.completedTrickCount - 1)
        )
        pendingAdvance = pending
        scheduleTrickResultHoldClear(for: pending)
    }

    private func talonBeforeCompletedTrick(
        _ trick: Trick,
        projection: PlayerGameProjection
    ) -> [ProjectedCard]? {
        guard trick.talonLead != nil else { return nil }
        let visibleCount = max(1, projection.completedTrickCount)
        return projection.talon.enumerated().map { index, card in
            index < visibleCount ? card : .hidden
        }
    }

    private func scheduleTrickResultHoldClear(for pending: PendingAdvance) {
        pendingAdvanceTask?.cancel()
        guard trickResultHoldDuration > .zero else {
            pendingAdvance = nil
            pendingAdvanceTask = nil
            return
        }

        let duration = trickResultHoldDuration
        pendingAdvanceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, self.pendingAdvance == pending else { return }
            self.pendingAdvance = nil
            self.pendingAdvanceTask = nil
        }
    }

    private func phaseOverrideForCompletedTrick(_ trick: Trick, in projection: PlayerGameProjection) -> ProjectedPhase? {
        switch projection.phase {
        case .playing:
            return nil
        case let .dealFinished(result):
            return playingPhase(for: result, trick: trick)
        case let .gameOver(summary):
            return playingPhase(for: summary.lastDeal, trick: trick)
        default:
            return nil
        }
    }

    private func playingPhase(for result: DealResult, trick: Trick) -> ProjectedPhase {
        .playing(
            currentPlayer: trick.winner,
            leader: trick.winner,
            kind: playKind(for: result)
        )
    }

    private func playKind(for result: DealResult) -> ProjectedPlayKind {
        switch result.kind {
        case let .game(declarer, contract, whisters):
            return .game(
                declarer: declarer,
                contract: contract,
                defenders: result.activePlayers.filter { $0 != declarer },
                whisters: whisters,
                defenderPlayMode: .closed
            )
        case let .misere(declarer):
            return .misere(declarer: declarer)
        case .allPass:
            return .allPass
        case let .halfWhist(declarer, contract, halfWhister):
            return .game(
                declarer: declarer,
                contract: contract,
                defenders: result.activePlayers.filter { $0 != declarer },
                whisters: [halfWhister],
                defenderPlayMode: .closed
            )
        case .passedOut, .withoutThree:
            return .allPass
        }
    }

    private func refreshPeersFromTransport() {
        guard let transport else { return }
        roster.refresh(with: transport.participants)
        recomputeRoster()
    }

    private func refreshPeerMapping(peer: OnlinePeer, identity: PlayerIdentity) async {
        roster.claim(peer: peer, as: identity)
        await hostActor?.updateIdentities(roster.seats)
        recomputeRoster()
    }

    private func shouldAcceptHello(from sender: OnlinePeer, identity: PlayerIdentity) -> Bool {
        roster.acceptsHello(from: sender, identity: identity)
    }

    private func adoptParticipantRoster(_ participants: [OnlinePeer]) {
        roster.adopt(participants)
        recomputeRoster()
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
        roster.isReadyToStart
    }

    private func logOnlineFlowProjection(_ projection: PlayerGameProjection, source: String) {
        logOnlineFlow(
            "event=projection source=\(source) local=\(localSeat?.rawValue ?? "unknown") viewer=\(projection.viewer.rawValue) sequence=\(projection.sequence) phase=\(projection.phase.token) tableID=\(projection.tableID.uuidString)"
        )
    }

    private func logOnlineFlow(_ message: String) {
        if ProcessInfo.processInfo.arguments.contains(UITestFlags.onlineFlowLogging) {
            let line = "ONLINE_FLOW \(message)"
            print(line)
            onlineFlowLogger.notice("\(line, privacy: .public)")
        }
    }

}
