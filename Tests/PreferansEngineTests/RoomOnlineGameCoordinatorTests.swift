import XCTest
@testable import PreferansApp
@testable import PreferansEngine

@MainActor
final class RoomOnlineGameCoordinatorTests: XCTestCase {
    private let peers: [OnlinePeer] = [
        OnlinePeer(playerID: "north", accountID: "dev:north@example.test", provider: .dev, displayName: "North"),
        OnlinePeer(playerID: "east", accountID: "dev:east@example.test", provider: .dev, displayName: "East"),
        OnlinePeer(playerID: "south", accountID: "dev:south@example.test", provider: .dev, displayName: "South")
    ]

    func testNoServerRoomPublishesRedactedProjectionsToEverySeat() async throws {
        let fixture = try await makeFixture()

        fixture.coordinators["north"]?.send(.startDeal(dealer: nil, deck: nil))
        await pump(until: { fixture.allProjectionsAre(at: 1) })

        let eastProjection = try XCTUnwrap(fixture.coordinators["east"]?.projection)
        XCTAssertEqual(eastProjection.viewer, "east")
        XCTAssertEqual(eastProjection.tableID, fixture.coordinators["north"]?.tableID)
        XCTAssertTrue(
            fixture.coordinators["east"]?.recentEvents.contains { event in
                if case .dealStarted = event { return true }
                return false
            } == true,
            "Online projection updates should carry the structured event stream, not only text summaries."
        )

        let eastSeat = try XCTUnwrap(eastProjection.seats.first { $0.player == "east" })
        XCTAssertEqual(eastSeat.hand.compactMap(\.knownCard).count, 10)

        let northSeat = try XCTUnwrap(eastProjection.seats.first { $0.player == "north" })
        XCTAssertEqual(northSeat.hand.count, 10)
        XCTAssertTrue(northSeat.hand.allSatisfy { $0.knownCard == nil })
    }

    func testLateCloudflareJoinRefreshesPeerRouteBeforeHostPublishes() async throws {
        let hostPeer = peers[0]
        let pendingEast = OnlinePeer(
            playerID: "east",
            accountID: "pending:east",
            provider: .dev,
            displayName: "East"
        )
        let actualEast = OnlinePeer(
            playerID: "east",
            accountID: "anonymous:east:joined",
            provider: .dev,
            displayName: "East"
        )
        let pendingSouth = OnlinePeer(
            playerID: "south",
            accountID: "pending:south",
            provider: .dev,
            displayName: "South"
        )
        let room = AccountAddressedRoom(hostPlayerID: "north")
        let hostTransport = room.transport(
            localPeer: hostPeer,
            participants: [hostPeer, pendingEast, pendingSouth]
        )
        let hostCoordinator = RoomOnlineGameCoordinator(
            dealSource: ScriptedDealSource(decks: [Deck.standard32])
        )

        await hostCoordinator.attach(transport: hostTransport)
        await pump(until: { hostCoordinator.projection?.sequence == 0 })

        let eastTransport = room.transport(
            localPeer: actualEast,
            participants: [hostPeer, actualEast, pendingSouth]
        )
        let eastCoordinator = RoomOnlineGameCoordinator()

        await eastCoordinator.attach(transport: eastTransport)
        await pump(until: { eastCoordinator.projection?.sequence == 0 })

        hostCoordinator.send(.startDeal(dealer: nil, deck: nil))
        await pump(until: { eastCoordinator.projection?.sequence == 1 })

        XCTAssertEqual(eastCoordinator.projection?.viewer, "east")
        XCTAssertEqual(eastCoordinator.projection?.tableID, hostCoordinator.tableID)
    }

    func testWaitingRoomRosterReflectsLaterJoinViaPresence() async throws {
        // A guest (east) is seated while south is still an unclaimed `pending:`
        // seat. This reproduces the stale-roster bug: a guest that joined before
        // south must still see south fill in when a later presence broadcast
        // arrives, rather than freezing on the roster it saw at its own join.
        let host = OnlinePeer(playerID: "north", accountID: "dev:north", provider: .dev, displayName: "North")
        let east = OnlinePeer(playerID: "east", accountID: "dev:east", provider: .dev, displayName: "East")
        let pendingSouth = OnlinePeer(playerID: "south", accountID: "pending:south", provider: .dev, displayName: "South")
        let joinedSouth = OnlinePeer(playerID: "south", accountID: "anonymous:south:joined", provider: .dev, displayName: "Sue")

        let transport = PresenceDrivenTransport(
            localPeer: east,
            hostPlayerID: "north",
            participants: [host, east, pendingSouth]
        )
        let coordinator = RoomOnlineGameCoordinator(heartbeat: .disabled, runsServerSideBots: false)
        await coordinator.attach(transport: transport)

        // Before anyone claims south, the guest renders it as an open seat.
        XCTAssertEqual(
            coordinator.rosterSeats.first { $0.player == "south" }?.occupancy,
            .openWaiting
        )

        // The relay broadcasts presence with south now claimed by a human.
        transport.simulatePresence([host, east, joinedSouth])
        await pump(until: {
            coordinator.rosterSeats.first { $0.player == "south" }?.occupancy == .human(name: "Sue")
        })
    }

    func testClientActionFlowsThroughHostAndSpoofedActorIsRejected() async throws {
        let fixture = try await makeFixture()

        fixture.coordinators["north"]?.send(.startDeal(dealer: nil, deck: nil))
        await pump(until: { fixture.allProjectionsAre(at: 1) })

        let firstBidder = try currentBidder(in: XCTUnwrap(fixture.coordinators["north"]?.projection))
        fixture.coordinators[firstBidder]?.send(.bid(player: firstBidder, call: .pass))
        await pump(until: { fixture.allProjectionsAre(at: 2) })

        let hostProjection = try XCTUnwrap(fixture.coordinators["north"]?.projection)
        XCTAssertEqual(hostProjection.auction.map(\.player), [firstBidder])

        let nextBidder = try currentBidder(in: hostProjection)
        let spoofingSender = try XCTUnwrap(peers.first { $0.playerID != nextBidder }?.playerID)
        fixture.coordinators[spoofingSender]?.send(.bid(player: nextBidder, call: .pass))
        await pump(until: {
            fixture.coordinators[spoofingSender]?.errorText?.contains("Action actor mismatch") == true
        })

        XCTAssertEqual(fixture.coordinators["north"]?.projection?.sequence, 2)
        XCTAssertEqual(fixture.coordinators["east"]?.projection?.sequence, 2)
        XCTAssertEqual(fixture.coordinators["south"]?.projection?.sequence, 2)
    }

    func testDuplicateClientNonceIsRejectedWithoutAdvancingHostSequence() async throws {
        let fixture = try await makeFixture()

        fixture.coordinators["north"]?.send(.startDeal(dealer: nil, deck: nil))
        await pump(until: { fixture.allProjectionsAre(at: 1) })

        var sequence = 1
        var projection = try XCTUnwrap(fixture.coordinators["north"]?.projection)
        var bidder = try currentBidder(in: projection)
        if bidder == fixture.hostPeer.playerID {
            fixture.coordinators[bidder]?.send(.bid(player: bidder, call: .pass))
            sequence += 1
            await pump(until: { fixture.allProjectionsAre(at: sequence) })
            projection = try XCTUnwrap(fixture.coordinators["north"]?.projection)
            bidder = try currentBidder(in: projection)
        }
        XCTAssertNotEqual(bidder, fixture.hostPeer.playerID)

        let tableID = try XCTUnwrap(fixture.coordinators["north"]?.tableID)
        let nonce = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let envelope = ClientActionEnvelope(
            tableID: tableID,
            actor: bidder,
            action: .bid(player: bidder, call: .pass),
            clientNonce: nonce,
            baseHostSequence: sequence
        )

        try await fixture.transports[bidder]?.send(.clientAction(envelope), to: [fixture.hostPeer], reliably: true)
        sequence += 1
        await pump(until: { fixture.allProjectionsAre(at: sequence) })

        try await fixture.transports[bidder]?.send(.clientAction(envelope), to: [fixture.hostPeer], reliably: true)
        await pump(until: {
            fixture.coordinators[bidder]?.errorText?.contains("Duplicate action nonce") == true
        })

        XCTAssertEqual(fixture.coordinators["north"]?.projection?.sequence, sequence)
        XCTAssertEqual(fixture.coordinators[bidder]?.projection?.sequence, sequence)
    }

    func testClientFlagsHostUnreachableWhenHostGoesSilent() async throws {
        let room = InMemoryRoom(peers: peers, hostPlayerID: "north")
        let hostTransport = try room.transport(for: "north")
        let eastTransport = try room.transport(for: "east")
        let southTransport = try room.transport(for: "south")

        let host = RoomOnlineGameCoordinator(
            dealSource: ScriptedDealSource(decks: [Deck.standard32]),
            heartbeat: .disabled
        )
        let east = RoomOnlineGameCoordinator(
            heartbeat: HeartbeatConfig(interval: .milliseconds(10), hostTimeout: .milliseconds(50))
        )
        let south = RoomOnlineGameCoordinator(heartbeat: .disabled)

        await host.attach(transport: hostTransport)
        await east.attach(transport: eastTransport)
        await south.attach(transport: southTransport)

        // The host's initial seat assignment + projection count as contact.
        await pump(until: { east.liveness == .live })

        // Host process vanishes — no more projections or ping echoes reach east.
        hostTransport.disconnect()

        await pump(until: { east.liveness == .hostUnreachable }, timeout: .seconds(1))
        XCTAssertEqual(east.liveness, .hostUnreachable)
        XCTAssertEqual(
            host.liveness,
            .live,
            "The host is the authority and must never flag itself unreachable."
        )

        east.detach()
        south.detach()
        host.detach()
    }

    func testClientResyncsAfterRecoveringFromAStalledSocket() async throws {
        let room = StallableRoom(peers: peers, hostPlayerID: "north")
        let hostTransport = room.transport(for: "north")
        let clientTransport = room.transport(for: "east")
        let southTransport = room.transport(for: "south")

        let host = RoomOnlineGameCoordinator(
            dealSource: ScriptedDealSource(decks: [Deck.standard32]),
            heartbeat: .disabled
        )
        let client = RoomOnlineGameCoordinator(
            heartbeat: HeartbeatConfig(interval: .milliseconds(10), hostTimeout: .milliseconds(50))
        )
        let south = RoomOnlineGameCoordinator(heartbeat: .disabled)

        await host.attach(transport: hostTransport)
        await client.attach(transport: clientTransport)
        await south.attach(transport: southTransport)
        await pump(until: { client.liveness == .live })

        let resyncsBeforeStall = clientTransport.resyncRequestCount

        // The socket dies: nothing flows in or out.
        clientTransport.isStalled = true
        await pump(until: { client.liveness == .hostUnreachable }, timeout: .seconds(1))

        // The socket recovers (auto-reconnect, in production).
        clientTransport.isStalled = false
        await pump(until: { client.liveness == .live }, timeout: .seconds(1))
        await pump(until: { clientTransport.resyncRequestCount > resyncsBeforeStall }, timeout: .seconds(1))

        XCTAssertEqual(client.liveness, .live)
        XCTAssertGreaterThan(
            clientTransport.resyncRequestCount,
            resyncsBeforeStall,
            "On recovery the client must pull a fresh projection to catch up on anything missed."
        )

        host.detach()
        client.detach()
        south.detach()
    }

    func testHostPersistsThroughArchiveStoreProtocol() async throws {
        let archiveStore = FakeGameArchiveStore()
        let fixture = try await makeFixture(hostArchiveStore: archiveStore)
        let hostCoordinator = try XCTUnwrap(fixture.coordinators["north"])
        let tableID = try XCTUnwrap(hostCoordinator.tableID)

        let initialSummary = await archiveStore.savedSummary(tableID: tableID)
        XCTAssertEqual(initialSummary?.lastSequence, 0)
        let initialPublicProjection = await archiveStore.latestPublicProjection(tableID: tableID)
        XCTAssertNotNil(initialPublicProjection)

        hostCoordinator.send(.startDeal(dealer: nil, deck: nil))
        await pump(until: { fixture.allProjectionsAre(at: 1) })

        for _ in 0..<50 {
            let actions = await archiveStore.savedActions(tableID: tableID)
            let snapshot = await archiveStore.savedSnapshot(tableID: tableID)
            if actions.count == 1, snapshot?.sequence == 1 { break }
            await Task.yield()
        }

        let actions = await archiveStore.savedActions(tableID: tableID)
        XCTAssertEqual(actions.map(\.sequence), [1])
        XCTAssertEqual(actions.first?.actor, "north")

        let savedSnapshot = await archiveStore.savedSnapshot(tableID: tableID)
        let snapshot = try XCTUnwrap(savedSnapshot)
        XCTAssertEqual(snapshot.sequence, 1)

        let updatedSummary = await archiveStore.savedSummary(tableID: tableID)
        XCTAssertEqual(updatedSummary?.lastSequence, 1)
    }

    func testInMemorySessionAutomatesRemotePeersThroughRoomTransport() async throws {
        let session = try InMemoryOnlineGameSession(
            peers: peers,
            localPlayerID: "east",
            hostPlayerID: "east",
            automatedPlayerIDs: ["north", "south"],
            dealSource: ScriptedDealSource(decks: [Deck.standard32]),
            botDelay: .zero
        )
        try await session.start()
        defer { session.stop() }

        session.localCoordinator.send(.startDeal(dealer: nil, deck: nil))
        await pump(until: { session.localCoordinator.projection?.sequence ?? 0 >= 1 })

        if let projection = session.localCoordinator.projection,
           case let .bidding(currentPlayer, _) = projection.phase,
           currentPlayer == session.localPeer.playerID {
            session.localCoordinator.send(.bid(player: currentPlayer, call: .pass))
        }

        await pump(until: { session.localCoordinator.projection?.sequence ?? 0 >= 2 })

        let projection = try XCTUnwrap(session.localCoordinator.projection)
        XCTAssertGreaterThanOrEqual(projection.sequence, 2)
        XCTAssertFalse(
            projection.auction.isEmpty,
            "At least one bid should cross the room transport after the deal starts."
        )
    }

    func testPlayerRoomSettlementCollectsAcceptancesAndScoresDeal() async throws {
        let fixture = try await makeFixture()
        // A misère is settleable by everyone at the table, so the room reaches
        // an eligible position without having to play any tricks first.
        var sequence = try await driveRoomToPlaying(fixture, openingBid: .misere)
        try await driveRoomToForcedSettlement(fixture, sequence: &sequence)
        let proposalProjection = try XCTUnwrap(fixture.coordinators["north"]?.projection)
        let activePlayers = proposalProjection.seats.filter(\.isActive).map(\.player)
        let proposer = try XCTUnwrap(activePlayers.first)
        let settlement = try XCTUnwrap(
            fixture.coordinators[proposer]?.projection?.legal.settlementOptions.first
        )

        try await apply(
            .proposeSettlement(player: proposer, settlement: settlement),
            from: proposer,
            in: fixture,
            sequence: &sequence
        )

        for player in activePlayers where player != proposer {
            let playerProjection = try XCTUnwrap(fixture.coordinators[player]?.projection)
            XCTAssertEqual(playerProjection.legal.pendingSettlement?.settlement, settlement)
            XCTAssertTrue(playerProjection.legal.canAcceptSettlement)
            try await apply(
                .acceptSettlement(player: player),
                from: player,
                in: fixture,
                sequence: &sequence
            )
        }

        for coordinator in fixture.coordinators.values {
            guard case let .dealFinished(result) = coordinator.projection?.phase else {
                return XCTFail("expected every player projection to show a scored settlement")
            }
            XCTAssertEqual(result.settlement, settlement)
            XCTAssertTrue(result.completedTricks.isEmpty)
        }
    }

    func testOnlineDisplayProjectionHoldsCompletedTrickResult() async throws {
        let fixture = try await makeFixture(trickResultHoldDuration: .seconds(30))
        var sequence = try await driveRoomToPlaying(fixture)
        let host = try XCTUnwrap(fixture.coordinators["north"])
        let completedBefore = host.projection?.completedTrickCount ?? 0

        for _ in 0..<4 {
            guard let action = nextRoomPlayAction(in: fixture) else {
                return XCTFail("Expected a legal card play while driving the first trick.")
            }
            try await apply(action.action, from: action.sender, in: fixture, sequence: &sequence)
            if (host.projection?.completedTrickCount ?? 0) > completedBefore {
                break
            }
        }

        let authoritative = try XCTUnwrap(host.projection)
        let pending = try XCTUnwrap(host.pendingAdvance)
        let display = try XCTUnwrap(host.displayProjection)

        XCTAssertTrue(authoritative.currentTrick.isEmpty)
        XCTAssertEqual(pending.trickPlays?.count, authoritative.seats.filter(\.isActive).count)
        XCTAssertEqual(display.currentTrick, pending.trickPlays)
        XCTAssertEqual(display.completedTrickCount, completedBefore)
        XCTAssertTrue(display.legal.playableCards.isEmpty)
        XCTAssertFalse(display.legal.canStartDeal)

        let winner = try XCTUnwrap(pending.trickWinner)
        let authoritativeWinnerCount = try XCTUnwrap(
            authoritative.seats.first { $0.player == winner }?.trickCount
        )
        let displayWinnerCount = try XCTUnwrap(
            display.seats.first { $0.player == winner }?.trickCount
        )
        XCTAssertEqual(displayWinnerCount, max(0, authoritativeWinnerCount - 1))
    }

    private func makeFixture(
        hostArchiveStore: (any GameArchiveStore)? = nil,
        trickResultHoldDuration: Duration = .milliseconds(1_400)
    ) async throws -> RoomFixture {
        let room = InMemoryRoom(peers: peers, hostPlayerID: "north")
        let transports = try Dictionary(uniqueKeysWithValues: peers.map { peer in
            (peer.playerID, try room.transport(for: peer.playerID))
        })
        let coordinators: [PlayerID: RoomOnlineGameCoordinator] = Dictionary(uniqueKeysWithValues: peers.map { peer in
            let archiveStore: (any GameArchiveStore)? = peer.playerID == "north" ? hostArchiveStore : nil
            return (
                peer.playerID,
                RoomOnlineGameCoordinator(
                    cloudStore: archiveStore,
                    dealSource: ScriptedDealSource(decks: [Deck.standard32]),
                    trickResultHoldDuration: trickResultHoldDuration
                )
            )
        })

        for peer in peers {
            try await coordinators[peer.playerID]?.attach(
                transport: XCTUnwrap(transports[peer.playerID])
            )
        }
        await pump(until: {
            coordinators.values.allSatisfy { $0.projection != nil }
        })

        return RoomFixture(
            hostPeer: try XCTUnwrap(peers.first { $0.playerID == "north" }),
            transports: transports,
            coordinators: coordinators
        )
    }

    private func pump(
        until condition: @MainActor () -> Bool,
        timeout: Duration = .milliseconds(750),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            await Task.yield()
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    private func currentBidder(in projection: PlayerGameProjection) throws -> PlayerID {
        guard case let .bidding(currentPlayer, _) = projection.phase else {
            throw EngineTestError("Expected bidding projection, got \(projection.phase).")
        }
        return currentPlayer
    }

    private func driveRoomToPlaying(
        _ fixture: RoomFixture,
        openingBid: ContractBid = .game(GameContract(6, .suit(.clubs)))
    ) async throws -> Int {
        var sequence = 0
        try await apply(.startDeal(dealer: nil, deck: nil), from: "north", in: fixture, sequence: &sequence)

        var projection = try XCTUnwrap(fixture.coordinators["north"]?.projection)
        let openingBidder = try currentBidder(in: projection)
        try await apply(
            .bid(player: openingBidder, call: .bid(openingBid)),
            from: openingBidder,
            in: fixture,
            sequence: &sequence
        )

        for _ in 0..<12 {
            projection = try XCTUnwrap(fixture.coordinators["north"]?.projection)
            switch projection.phase {
            case let .bidding(currentPlayer, _):
                try await apply(.bid(player: currentPlayer, call: .pass), from: currentPlayer, in: fixture, sequence: &sequence)

            case let .awaitingDiscard(declarer, _):
                let declarerProjection = try XCTUnwrap(fixture.coordinators[declarer]?.projection)
                let talon = declarerProjection.talon.compactMap(\.knownCard)
                try await apply(.discard(player: declarer, cards: talon), from: declarer, in: fixture, sequence: &sequence)

            case let .awaitingContract(declarer, _):
                let declarerProjection = try XCTUnwrap(fixture.coordinators[declarer]?.projection)
                let contract = try XCTUnwrap(declarerProjection.legal.contractOptions.first)
                try await apply(.declareContract(player: declarer, contract: contract), from: declarer, in: fixture, sequence: &sequence)

            case let .awaitingWhist(currentPlayer, _, _):
                let whistProjection = try XCTUnwrap(fixture.coordinators[currentPlayer]?.projection)
                let call = whistProjection.legal.whistCalls.contains(.whist)
                    ? WhistCall.whist
                    : try XCTUnwrap(whistProjection.legal.whistCalls.first)
                try await apply(.whist(player: currentPlayer, call: call), from: currentPlayer, in: fixture, sequence: &sequence)

            case let .awaitingDefenderMode(whister, _):
                try await apply(.chooseDefenderMode(player: whister, mode: .closed), from: whister, in: fixture, sequence: &sequence)

            case .playing:
                return sequence

            case .waitingForDeal, .dealFinished, .gameOver:
                throw EngineTestError("Expected to reach playing, got \(projection.phase).")
            }
        }
        throw EngineTestError("Room flow did not reach playing within the bounded setup loop.")
    }

    private func driveRoomToForcedSettlement(_ fixture: RoomFixture, sequence: inout Int) async throws {
        for _ in 0..<32 {
            if fixture.coordinators.values.contains(where: { coordinator in
                coordinator.projection?.legal.settlementOptions.isEmpty == false
            }) {
                return
            }
            guard let action = nextRoomPlayAction(in: fixture) else {
                break
            }
            try await apply(action.action, from: action.sender, in: fixture, sequence: &sequence)
        }
        throw EngineTestError("Room flow did not reach a forced settlement position.")
    }

    private func nextRoomPlayAction(in fixture: RoomFixture) -> (sender: PlayerID, action: PreferansAction)? {
        for (viewer, coordinator) in fixture.coordinators {
            guard let projection = coordinator.projection,
                  case let .playing(currentPlayer, _, _) = projection.phase,
                  let card = projection.legal.playableCards.first else {
                continue
            }
            let owner = projection.legal.playableCardsOwner ?? currentPlayer
            return (viewer, .playCard(player: owner, card: card))
        }
        return nil
    }

    private func apply(
        _ action: PreferansAction,
        from player: PlayerID,
        in fixture: RoomFixture,
        sequence: inout Int
    ) async throws {
        let coordinator = try XCTUnwrap(fixture.coordinators[player])
        coordinator.send(action)
        sequence += 1
        await pump(until: { fixture.allProjectionsAre(at: sequence) })
    }
}

@MainActor
private struct RoomFixture {
    var hostPeer: OnlinePeer
    var transports: [PlayerID: InMemoryRoomTransport]
    var coordinators: [PlayerID: RoomOnlineGameCoordinator]

    func allProjectionsAre(at sequence: Int) -> Bool {
        coordinators.values.allSatisfy { $0.projection?.sequence == sequence }
    }
}

/// In-memory room whose per-seat transports can be individually "stalled" to
/// model a dead socket — inbound and outbound traffic are both dropped while
/// stalled, then resume on recovery. Lets coordinator tests exercise the
/// reconnect/resync path without a real WebSocket.
@MainActor
private final class StallableRoom {
    let peers: [OnlinePeer]
    let hostPlayerID: PlayerID
    private var transports: [PlayerID: StallableTransport] = [:]

    init(peers: [OnlinePeer], hostPlayerID: PlayerID) {
        self.peers = peers
        self.hostPlayerID = hostPlayerID
    }

    func transport(for playerID: PlayerID) -> StallableTransport {
        let peer = peers.first { $0.playerID == playerID } ?? peers[0]
        let transport = StallableTransport(room: self, localPeer: peer, hostPlayerID: hostPlayerID)
        transports[playerID] = transport
        return transport
    }

    fileprivate func deliver(_ message: GameWireMessage, from sender: OnlinePeer, to recipients: [OnlinePeer]) {
        for recipient in recipients where recipient.playerID != sender.playerID {
            transports[recipient.playerID]?.receive(ReceivedRoomMessage(message: message, sender: sender))
        }
    }
}

@MainActor
private final class StallableTransport: RoomRealtimeTransport {
    let localPeer: OnlinePeer
    let participants: [OnlinePeer]
    /// While true, the socket is treated as down: sends are recorded but not
    /// delivered, and inbound messages are dropped.
    var isStalled = false
    private(set) var sentMessages: [GameWireMessage] = []

    private let room: StallableRoom
    private let hostPlayerID: PlayerID
    private var continuations: [UUID: AsyncStream<ReceivedRoomMessage>.Continuation] = [:]
    private var backlog: [ReceivedRoomMessage] = []

    init(room: StallableRoom, localPeer: OnlinePeer, hostPlayerID: PlayerID) {
        self.room = room
        self.localPeer = localPeer
        self.participants = room.peers
        self.hostPlayerID = hostPlayerID
    }

    var resyncRequestCount: Int {
        sentMessages.filter { if case .resyncRequest = $0 { return true } else { return false } }.count
    }

    func chooseHost() async -> OnlinePeer? {
        participants.first { $0.playerID == hostPlayerID }
    }

    func messages() -> AsyncStream<ReceivedRoomMessage> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            for message in backlog { continuation.yield(message) }
            backlog.removeAll()
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations.removeValue(forKey: id) }
            }
        }
    }

    func send(_ message: GameWireMessage, to peers: [OnlinePeer], reliably: Bool) async throws {
        sentMessages.append(message)
        guard !isStalled else { return }
        room.deliver(message, from: localPeer, to: peers)
    }

    func sendToAll(_ message: GameWireMessage, reliably: Bool) async throws {
        sentMessages.append(message)
        guard !isStalled else { return }
        room.deliver(message, from: localPeer, to: participants)
    }

    func disconnect() {
        for continuation in continuations.values { continuation.finish() }
        continuations.removeAll()
        backlog.removeAll()
    }

    fileprivate func receive(_ message: ReceivedRoomMessage) {
        guard !isStalled else { return }
        if continuations.isEmpty {
            backlog.append(message)
        } else {
            for continuation in continuations.values { continuation.yield(message) }
        }
    }
}

@MainActor
private final class AccountAddressedRoom {
    private let hostPlayerID: PlayerID
    private var transports: [String: AccountAddressedTransport] = [:]

    init(hostPlayerID: PlayerID) {
        self.hostPlayerID = hostPlayerID
    }

    func transport(localPeer: OnlinePeer, participants: [OnlinePeer]) -> AccountAddressedTransport {
        let transport = AccountAddressedTransport(
            room: self,
            localPeer: localPeer,
            participants: participants,
            hostPlayerID: hostPlayerID
        )
        transports[localPeer.accountID] = transport
        return transport
    }

    fileprivate func deliver(_ message: GameWireMessage, from sender: OnlinePeer, to recipients: [OnlinePeer]) {
        for recipient in recipients where recipient.accountID != sender.accountID {
            transports[recipient.accountID]?.receive(ReceivedRoomMessage(message: message, sender: sender))
        }
    }

    fileprivate func broadcast(_ message: GameWireMessage, from sender: OnlinePeer) {
        for transport in transports.values where transport.localPeer.accountID != sender.accountID {
            transport.receive(ReceivedRoomMessage(message: message, sender: sender))
        }
    }
}

@MainActor
private final class AccountAddressedTransport: RoomRealtimeTransport {
    public let localPeer: OnlinePeer
    public let participants: [OnlinePeer]

    private let room: AccountAddressedRoom
    private let hostPlayerID: PlayerID
    private var continuations: [UUID: AsyncStream<ReceivedRoomMessage>.Continuation] = [:]
    private var backlog: [ReceivedRoomMessage] = []

    init(
        room: AccountAddressedRoom,
        localPeer: OnlinePeer,
        participants: [OnlinePeer],
        hostPlayerID: PlayerID
    ) {
        self.room = room
        self.localPeer = localPeer
        self.participants = participants
        self.hostPlayerID = hostPlayerID
    }

    func chooseHost() async -> OnlinePeer? {
        participants.first { $0.playerID == hostPlayerID }
    }

    func messages() -> AsyncStream<ReceivedRoomMessage> {
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

    func send(_ message: GameWireMessage, to peers: [OnlinePeer], reliably: Bool) async throws {
        room.deliver(message, from: localPeer, to: peers)
    }

    func sendToAll(_ message: GameWireMessage, reliably: Bool) async throws {
        room.broadcast(message, from: localPeer)
    }

    func disconnect() {
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
        backlog.removeAll()
    }

    fileprivate func receive(_ message: ReceivedRoomMessage) {
        if continuations.isEmpty {
            backlog.append(message)
        } else {
            for continuation in continuations.values {
                continuation.yield(message)
            }
        }
    }
}

/// A transport whose roster can change after attach, mirroring the Cloudflare
/// relay pushing a fresh presence snapshot. `simulatePresence` updates the roster
/// and notifies subscribers; `participantUpdates` replays the current roster on
/// subscribe so the coordinator can't miss a snapshot that landed first.
@MainActor
private final class PresenceDrivenTransport: RoomRealtimeTransport {
    let localPeer: OnlinePeer
    private(set) var participants: [OnlinePeer]

    private let hostPlayerID: PlayerID
    private var participantContinuations: [UUID: AsyncStream<[OnlinePeer]>.Continuation] = [:]

    init(localPeer: OnlinePeer, hostPlayerID: PlayerID, participants: [OnlinePeer]) {
        self.localPeer = localPeer
        self.hostPlayerID = hostPlayerID
        self.participants = participants
    }

    func chooseHost() async -> OnlinePeer? {
        participants.first { $0.playerID == hostPlayerID }
    }

    func messages() -> AsyncStream<ReceivedRoomMessage> {
        AsyncStream { $0.finish() }
    }

    func participantUpdates() -> AsyncStream<[OnlinePeer]> {
        let id = UUID()
        return AsyncStream { continuation in
            continuation.yield(participants)
            participantContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.participantContinuations.removeValue(forKey: id) }
            }
        }
    }

    func send(_ message: GameWireMessage, to peers: [OnlinePeer], reliably: Bool) async throws {}
    func sendToAll(_ message: GameWireMessage, reliably: Bool) async throws {}

    func disconnect() {
        for continuation in participantContinuations.values {
            continuation.finish()
        }
        participantContinuations.removeAll()
    }

    func simulatePresence(_ peers: [OnlinePeer]) {
        participants = peers
        for continuation in participantContinuations.values {
            continuation.yield(peers)
        }
    }
}
