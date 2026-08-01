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
    private let hostRecoveryBackoff: RoomRetryBackoff
    /// Invalidates async authority work whenever attachment or host ownership
    /// changes. Cancellation alone is insufficient because transport awaits do
    /// not all cooperate with task cancellation.
    private var authorityGeneration: UInt64 = 0
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
    private var hostLiveness = RoomHostLiveness()
    private let livenessClock = ContinuousClock()

    public init(
        dealSource: DealSource = RandomDealSource(),
        heartbeat: HeartbeatConfig = .default,
        botMoveDelay: Duration = BotPacing.interactive,
        trickResultHoldDuration: Duration = .milliseconds(1_400),
        durabilityRetryInitialDelay: Duration = .milliseconds(500),
        hostRecoveryRetryInitialDelay: Duration = .milliseconds(250),
        hostRecoveryRetryMaximumDelay: Duration = .seconds(4),
        runsServerSideBots: Bool = true
    ) {
        self.dealSource = dealSource
        self.heartbeat = heartbeat
        self.botMoveDelay = botMoveDelay
        self.trickResultHoldDuration = trickResultHoldDuration
        self.durabilityBarrier = RoomDurabilityBarrier(
            initialRetryDelay: durabilityRetryInitialDelay
        )
        self.hostRecoveryBackoff = RoomRetryBackoff(
            initialDelay: hostRecoveryRetryInitialDelay,
            maximumDelay: hostRecoveryRetryMaximumDelay
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
        // One coordinator represents exactly one attachment. Invalidate every
        // task and every visible table value before awaiting the new room's
        // host election; otherwise a reattach can leave the previous socket
        // connected and briefly expose its projection under the new identity.
        let authorityGeneration = resetAttachment(
            disconnectCurrentTransport: self.transport !== transport
        )
        // On resume the snapshot's rules are authoritative — adopt them so the
        // seat assignment we broadcast matches the engine we rebuild.
        self.rules = resume?.snapshot.rules ?? rules
        self.match = resume?.snapshot.match ?? match
        self.variantTag = variantTag
        self.errorText = nil
        self.state = .selectingHost
        resetHostLiveness()
        self.transportStatus = .connecting
        self.didAutoStartOnlineDeal = false
        self.transport = transport
        self.transportEventsTask = observeConnectionEvents(of: transport)
        self.listenTask = listen(to: transport)

        let participants = RoomParticipantRoster.ordered(transport.participants)
        self.roster = RoomParticipantRoster(participants: participants)
        self.localSeat = transport.localPeer.playerID
        recomputeRoster()

        let host = await transport.chooseHost() ?? participants.first ?? transport.localPeer
        guard self.transport === transport,
              self.authorityGeneration == authorityGeneration else { return }
        self.hostPeer = host
        self.isHost = host.playerID == transport.localPeer.playerID

        if isHost {
            do {
                try await becomeHost(
                    host: host,
                    seats: roster.seats,
                    rules: self.rules,
                    match: self.match,
                    resume: resume,
                    authorityGeneration: authorityGeneration,
                    transport: transport
                )
            } catch is CancellationError {
                await reconcileHostAuthority(using: transport)
            } catch {
                beginHostRecovery(as: host, using: transport)
            }
        } else {
            self.state = .connectedAsClient
            beginClientLiveness()
            await sendHello()
            startHeartbeat()
        }
        // Subscribe after the initial authority decision. The transport replays
        // its latest room state, so a migration that raced attach is still
        // observed without letting the replay compete with initial setup.
        self.participantsTask = observeParticipants(of: transport)
    }

    public func detach() {
        resetAttachment(disconnectCurrentTransport: true)
        transportStatus = .disconnected
        state = .disconnected
    }

    /// Tear down all work and presentation state owned by the current room.
    /// The authority generation advances before `disconnect()` because a
    /// transport may resume a non-cooperative durability await as it closes;
    /// that completion must already be stale when it reaches the coordinator.
    @discardableResult
    private func resetAttachment(disconnectCurrentTransport: Bool) -> UInt64 {
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
        heartbeatTask?.cancel()
        heartbeatTask = nil
        pendingBotTask?.cancel()
        pendingBotTask = nil
        pendingAdvanceTask?.cancel()
        pendingAdvanceTask = nil

        durabilityBarrier.reset()
        let generation = advanceAuthorityGeneration()
        let previousTransport = transport
        transport = nil
        if disconnectCurrentTransport {
            previousTransport?.disconnect()
        }

        hostActor = nil
        hostPeer = nil
        projection = nil
        pendingAdvance = nil
        eventLog = []
        recentEvents = []
        isHost = false
        localSeat = nil
        tableID = nil
        resetHostLiveness()
        didAutoStartOnlineDeal = false
        roster.reset()
        rosterSeats = []
        canHostStart = false
        return generation
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
        if hostLiveness.markUnreachableIfTimedOut(
            at: livenessClock.now,
            timeout: heartbeat.hostTimeout
        ) {
            publishHostLiveness()
        }
        try? await transport.send(.ping(PingEnvelope(tableID: tableID)), to: [hostPeer], reliably: false)
    }

    /// Record that we just heard from the host and clear any stall flag. When
    /// this is a *recovery* — we had flagged the host unreachable and contact
    /// just resumed (a reconnect, or the host coming back) — pull a fresh
    /// projection so we catch up on anything missed while we were away.
    private func noteHostContact() {
        guard !isHost else { return }
        let needsResync = hostLiveness.noteHostContact(at: livenessClock.now)
        publishHostLiveness()
        if needsResync {
            requestResync()
        }
    }

    private func resetHostLiveness() {
        hostLiveness.reset()
        publishHostLiveness()
    }

    private func beginClientLiveness() {
        hostLiveness.beginClientSession(at: livenessClock.now)
        publishHostLiveness()
    }

    private func publishHostLiveness() {
        if liveness != hostLiveness.status {
            liveness = hostLiveness.status
        }
    }

    private func becomeHost(
        host: OnlinePeer,
        seats: [PlayerIdentity],
        rules: PreferansRules,
        match: MatchSettings,
        resume: OnlineResumeContext? = nil,
        authorityGeneration: UInt64,
        transport: any RoomRealtimeTransport
    ) async throws {
        let tableID = UUID()
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
        // Establish durable truth before announcing this authority or exposing
        // its projection. Any client action built on a visible state must have
        // an already-recoverable snapshot behind it.
        let update = await actor.initialUpdate()
        try await reportStateToWorker(update, actor: actor, transport: transport)
        guard await stillOwnsHostAuthority(
            authorityGeneration,
            expectedHost: hostID,
            transport: transport
        ) else { throw CancellationError() }

        let assignment = SeatAssignmentEnvelope(
            tableID: tableID,
            hostPlayerID: hostID,
            seats: seats,
            rules: rules,
            match: match
        )
        try await transport.sendToAll(.seatAssignment(assignment), reliably: true)
        guard await stillOwnsHostAuthority(
            authorityGeneration,
            expectedHost: hostID,
            transport: transport
        ) else { throw CancellationError() }

        self.tableID = tableID
        self.hostActor = actor
        self.state = .connectedAsHost
        self.hostLiveness.becomeHost()
        self.publishHostLiveness()
        await publish(update, authorityGeneration: authorityGeneration)
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
                    self.hostRecoveryTask?.cancel()
                    self.hostRecoveryTask = nil
                    self.durabilityRetryTask?.cancel()
                    self.durabilityRetryTask = nil
                    self.durabilityBarrier.reset()
                    self.advanceAuthorityGeneration()
                    self.isHost = false
                    self.hostActor = nil
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
        guard self.transport === transport else { return }
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
        let authorityGeneration = advanceAuthorityGeneration()
        isHost = true
        state = .selectingHost
        resetHostLiveness()
        errorText = nil

        hostRecoveryTask = Task { @MainActor [weak self, weak transport] in
            guard let self, let transport else { return }
            var retryBackoff = self.hostRecoveryBackoff
            while !Task.isCancelled {
                do {
                    let resume = try await transport.hostRecoveryContext()
                    guard !Task.isCancelled,
                          let current = await transport.chooseHost(),
                          current.playerID == transport.localPeer.playerID,
                          self.hostPeer?.playerID == current.playerID,
                          self.authorityGeneration == authorityGeneration else { return }
                    if let resume {
                        self.rules = resume.snapshot.rules
                        self.match = resume.snapshot.match
                    }
                    try await self.becomeHost(
                        host: elected,
                        seats: self.roster.seats,
                        rules: self.rules,
                        match: self.match,
                        resume: resume,
                        authorityGeneration: authorityGeneration,
                        transport: transport
                    )
                    guard self.authorityGeneration == authorityGeneration else { return }
                    self.errorText = nil
                    self.hostRecoveryTask = nil
                    return
                } catch is CancellationError {
                    return
                } catch {
                    guard self.authorityGeneration == authorityGeneration,
                          self.isHost else { return }
                    self.errorText = String(
                        localized: "Recovering the table… Your game is safe."
                    )
                    try? await Task.sleep(for: retryBackoff.currentDelay)
                    retryBackoff.recordFailure()
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
        advanceAuthorityGeneration()
        pendingBotTask?.cancel()
        pendingBotTask = nil
        hostActor = nil
        isHost = false
        hostPeer = elected
        state = .connectedAsClient
        beginClientLiveness()
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
            let preProjection = projection
            tableID = envelope.tableID
            projection = envelope.projection
            beginTrickResultHoldIfNeeded(
                events: envelope.events,
                preProjection: preProjection,
                projection: envelope.projection
            )
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
        let authorityGeneration = self.authorityGeneration
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
                guard ownsHostAuthority(authorityGeneration) else { return }
                queueDurabilityRetry(
                    update,
                    after: error,
                    authorityGeneration: authorityGeneration
                )
                return
            }
            guard ownsHostAuthority(authorityGeneration), self.hostActor === hostActor else { return }
            await publish(update, authorityGeneration: authorityGeneration)
        } catch {
            await onError(error)
        }
    }

    private func queueDurabilityRetry(
        _ update: HostUpdate,
        after error: Error,
        authorityGeneration: UInt64
    ) {
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
                      self.ownsHostAuthority(authorityGeneration),
                      let pending = self.durabilityBarrier.update(for: ticket) else { return }
                do {
                    try await self.reportStateToWorker(pending)
                    guard self.ownsHostAuthority(authorityGeneration),
                          self.durabilityBarrier.update(for: ticket) != nil else { return }
                    await self.publish(pending, authorityGeneration: authorityGeneration)
                    guard self.ownsHostAuthority(authorityGeneration) else { return }
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

    private func publish(_ update: HostUpdate, authorityGeneration: UInt64) async {
        guard ownsHostAuthority(authorityGeneration) else { return }
        tableID = update.tableID
        refreshPeersFromTransport()
        if let localSeat, let localProjection = update.projections[localSeat] {
            let preProjection = projection
            projection = localProjection
            beginTrickResultHoldIfNeeded(
                events: update.events,
                preProjection: preProjection,
                projection: localProjection
            )
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
            guard ownsHostAuthority(authorityGeneration) else { return }
            guard let peer = roster.peer(for: viewer) else { continue }
            // Production hosts advance bot seats inside this coordinator, so
            // those seats have no socket. The in-memory room deliberately runs
            // each automated seat through a separate coordinator; when
            // server-side bots are disabled, their transports must receive the
            // same redacted projections as human peers.
            if peer.isBotSeat, runsServerSideBots { continue }
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
        try await reportStateToWorker(update, actor: hostActor, transport: transport)
    }

    private func reportStateToWorker(
        _ update: HostUpdate,
        actor hostActor: HostGameActor,
        transport: any RoomRealtimeTransport
    ) async throws {
        let snapshot = await hostActor.engineSnapshot
        let summary = RoomStateReportBuilder.summary(
            variantTag: variantTag,
            sequence: update.sequence,
            dealNumber: update.dealNumber,
            state: update.snapshot.state
        )
        try await transport.reportState(
            status: update.status,
            summary: summary,
            // A finished game is never resumed, so don't ship its snapshot.
            snapshot: update.status == .finished ? nil : snapshot,
            snapshotSequence: update.sequence
        )
    }

    @discardableResult
    private func advanceAuthorityGeneration() -> UInt64 {
        authorityGeneration &+= 1
        return authorityGeneration
    }

    private func ownsHostAuthority(_ generation: UInt64) -> Bool {
        isHost && authorityGeneration == generation
    }

    /// Re-check both local generation and server election around an await. A
    /// stale recovery task may resume even after cancellation if the transport
    /// call it was waiting on is not cancellation-aware.
    private func stillOwnsHostAuthority(
        _ generation: UInt64,
        expectedHost: PlayerID,
        transport: any RoomRealtimeTransport
    ) async -> Bool {
        guard ownsHostAuthority(generation),
              self.transport === transport,
              hostPeer?.playerID == expectedHost,
              !Task.isCancelled else { return false }
        let elected = await transport.chooseHost()
        return ownsHostAuthority(generation)
            && self.transport === transport
            && hostPeer?.playerID == expectedHost
            && elected?.playerID == expectedHost
            && !Task.isCancelled
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

    /// Online uses the same exact pre-action hold as local play, but clears it
    /// on a timer so one distracted player cannot stall the shared table.
    private func beginTrickResultHoldIfNeeded(
        events: [PreferansEvent],
        preProjection: PlayerGameProjection?,
        projection: PlayerGameProjection
    ) {
        guard let preProjection,
              preProjection.tableID == projection.tableID,
              let pending = AdvancePresentation.completedTrickHold(
                  events: events,
                  viewer: localSeat ?? projection.viewer,
                  preProjection: preProjection,
                  visibleTalonBeforeAction: preProjection.talon
              ) else { return }
        pendingAdvance = pending
        scheduleTrickResultHoldClear(for: pending)
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
