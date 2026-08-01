import XCTest
@testable import PreferansApp
@testable import PreferansEngine
@testable import PreferansEngineTestSupport

@MainActor
final class RoomOnlineGameCoordinatorTests: AppTestCase {
    func testSharedRetryBackoffDoublesCapsAndResets() {
        var backoff = RoomRetryBackoff(
            initialDelay: .milliseconds(250),
            maximumDelay: .seconds(1)
        )

        XCTAssertEqual(backoff.currentDelay, .milliseconds(250))
        backoff.recordFailure()
        XCTAssertEqual(backoff.currentDelay, .milliseconds(500))
        backoff.recordFailure()
        XCTAssertEqual(backoff.currentDelay, .seconds(1))
        backoff.recordFailure()
        XCTAssertEqual(backoff.currentDelay, .seconds(1))

        backoff.reset()
        XCTAssertEqual(backoff.currentDelay, .milliseconds(250))
    }

    func testSharedRetryBackoffNormalizesInvalidBounds() {
        let backoff = RoomRetryBackoff(
            initialDelay: .zero,
            maximumDelay: .seconds(-1)
        )

        XCTAssertEqual(backoff.initialDelay, .nanoseconds(1))
        XCTAssertEqual(backoff.currentDelay, .nanoseconds(1))
        XCTAssertEqual(backoff.maximumDelay, .nanoseconds(1))
    }

    func testDurabilityBarrierIsSingleFlightAndTicketScoped() {
        var barrier = RoomDurabilityBarrier<Int>(initialRetryDelay: .milliseconds(10))

        let first = try! XCTUnwrap(barrier.stage(11))
        XCTAssertFalse(barrier.acceptsAction)
        XCTAssertNil(barrier.stage(12))
        XCTAssertEqual(barrier.update(for: first), 11)
        XCTAssertEqual(barrier.delay(for: first), .milliseconds(10))

        XCTAssertEqual(barrier.complete(first), 11)
        XCTAssertTrue(barrier.acceptsAction)
        let second = try! XCTUnwrap(barrier.stage(12))
        XCTAssertNil(barrier.update(for: first))
        XCTAssertNil(barrier.complete(first), "a stale retry task must not clear the newer move")
        XCTAssertEqual(barrier.update(for: second), 12)
    }

    func testDurabilityBarrierBackoffCapsAndResetInvalidatesTicket() {
        var barrier = RoomDurabilityBarrier<Int>(
            initialRetryDelay: .seconds(1),
            maximumRetryDelay: .seconds(4)
        )
        let ticket = try! XCTUnwrap(barrier.stage(1))

        XCTAssertTrue(barrier.recordFailure(for: ticket))
        XCTAssertEqual(barrier.delay(for: ticket), .seconds(2))
        XCTAssertTrue(barrier.recordFailure(for: ticket))
        XCTAssertEqual(barrier.delay(for: ticket), .seconds(4))
        XCTAssertTrue(barrier.recordFailure(for: ticket))
        XCTAssertEqual(barrier.delay(for: ticket), .seconds(4))

        barrier.reset()
        XCTAssertTrue(barrier.acceptsAction)
        XCTAssertNil(barrier.delay(for: ticket))
        XCTAssertFalse(barrier.recordFailure(for: ticket))
    }

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

    func testRapidDuplicateStartDealDoesNotSurfaceInvalidState() async throws {
        let fixture = try await makeFixture()
        let host = try XCTUnwrap(fixture.coordinators["north"])

        host.send(.startDeal(dealer: nil, deck: nil))
        host.send(.startDeal(dealer: nil, deck: nil))
        await pump(until: { fixture.allProjectionsAre(at: 1) })

        XCTAssertNil(host.errorText)
        XCTAssertEqual(host.projection?.sequence, 1)
        guard let phase = host.projection?.phase, case .bidding = phase else {
            return XCTFail("Duplicate startDeal should leave the first deal in bidding.")
        }
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

    func testNewerDeviceTakeoverMakesTheStaleCoordinatorReadOnly() async throws {
        let host = OnlinePeer(playerID: "north", accountID: "dev:north", provider: .dev, displayName: "North")
        let east = OnlinePeer(playerID: "east", accountID: "dev:east", provider: .dev, displayName: "East")
        let south = OnlinePeer(playerID: "south", accountID: "dev:south", provider: .dev, displayName: "South")
        let transport = PresenceDrivenTransport(
            localPeer: host,
            hostPlayerID: "north",
            participants: [host, east, south]
        )
        let coordinator = RoomOnlineGameCoordinator(
            dealSource: ScriptedDealSource(decks: [Deck.standard32]),
            heartbeat: .disabled
        )
        await coordinator.attach(transport: transport)
        await pump(until: { coordinator.projection?.sequence == 0 })

        transport.simulateConnectionEvent(.seatTakenOver)
        await pump(until: { coordinator.transportStatus == .seatTakenOver })
        coordinator.send(.startDeal(dealer: nil, deck: nil))

        XCTAssertFalse(coordinator.isHost)
        XCTAssertEqual(coordinator.projection?.sequence, 0)
        XCTAssertTrue(coordinator.errorText?.contains("another device") == true)
        coordinator.detach()
    }

    func testVisibleProjectionWaitsForDurableSnapshotCommit() async throws {
        let host = OnlinePeer(playerID: "north", accountID: "dev:north", provider: .dev, displayName: "North")
        let east = OnlinePeer(playerID: "east", accountID: "dev:east", provider: .dev, displayName: "East")
        let south = OnlinePeer(playerID: "south", accountID: "dev:south", provider: .dev, displayName: "South")
        let transport = PresenceDrivenTransport(
            localPeer: host,
            hostPlayerID: "north",
            participants: [host, east, south]
        )
        let coordinator = RoomOnlineGameCoordinator(
            dealSource: ScriptedDealSource(decks: [Deck.standard32]),
            heartbeat: .disabled,
            durabilityRetryInitialDelay: .milliseconds(10)
        )
        await coordinator.attach(transport: transport)
        await pump(until: { coordinator.projection?.sequence == 0 })

        transport.blockedReportSequences.insert(1)
        coordinator.send(.startDeal(dealer: nil, deck: nil))
        await pump(until: { transport.events.contains("report-attempt:1") })

        XCTAssertEqual(coordinator.projection?.sequence, 0)
        XCTAssertFalse(transport.events.contains("projection:1"))
        XCTAssertTrue(coordinator.errorText?.contains("saving your move") == true)

        transport.blockedReportSequences.remove(1)
        await pump(until: { coordinator.projection?.sequence == 1 })

        let committed = try XCTUnwrap(transport.events.firstIndex(of: "report-commit:1"))
        let published = try XCTUnwrap(transport.events.firstIndex(of: "projection:1"))
        XCTAssertLessThan(committed, published)
        XCTAssertNil(coordinator.errorText)
        coordinator.detach()
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

    func testServerElectedSuccessorHydratesSnapshotAndContinuesTheSameDeal() async throws {
        let room = StallableRoom(peers: peers, hostPlayerID: "north")
        let transports = Dictionary(uniqueKeysWithValues: peers.map { peer in
            (peer.playerID, room.transport(for: peer.playerID))
        })
        let coordinators = Dictionary(uniqueKeysWithValues: peers.map { peer in
            (peer.playerID, RoomOnlineGameCoordinator(
                dealSource: ScriptedDealSource(decks: [Deck.standard32]),
                heartbeat: .disabled
            ))
        })

        for peer in peers {
            await coordinators[peer.playerID]?.attach(transport: try XCTUnwrap(transports[peer.playerID]))
        }
        let north = try XCTUnwrap(coordinators["north"])
        north.send(.startDeal(dealer: nil, deck: nil))
        await pump(until: { coordinators.values.allSatisfy { $0.projection?.sequence == 1 } })

        // Rebuild the exact state the worker persisted for sequence 1. The
        // successor must hydrate this snapshot; starting a fresh engine would
        // produce a different table state and fail the continuation below.
        let durableHost = try HostGameActor(
            hostPlayerID: "north",
            seats: peers.map(\.playerIdentity),
            dealSource: ScriptedDealSource(decks: [Deck.standard32])
        )
        let durableUpdate = try await durableHost.applyClientAction(
            ClientActionEnvelope(
                tableID: durableHost.tableID,
                actor: "north",
                action: .startDeal(dealer: nil, deck: nil),
                baseHostSequence: 0
            ),
            sender: "north"
        )
        let durableSnapshot = await durableHost.engineSnapshot
        XCTAssertEqual(durableUpdate.sequence, 1)

        room.migrateHost(
            to: "east",
            recovery: OnlineResumeContext(snapshot: durableSnapshot, sequence: durableUpdate.sequence)
        )

        let east = try XCTUnwrap(coordinators["east"])
        await pump(until: {
            east.isHost &&
            east.state == .connectedAsHost &&
            east.projection?.sequence == 1 &&
            north.isHost == false
        })
        let migratedTableID = try XCTUnwrap(east.tableID)
        await pump(until: {
            coordinators.values.allSatisfy {
                $0.tableID == migratedTableID &&
                $0.projection?.tableID == migratedTableID &&
                $0.projection?.sequence == 1
            }
        })

        let projection = try XCTUnwrap(east.projection)
        let bidder = try currentBidder(in: projection)
        try XCTUnwrap(coordinators[bidder]).send(.bid(player: bidder, call: .pass))
        await pump(until: { coordinators.values.allSatisfy { $0.projection?.sequence == 2 } })

        XCTAssertEqual(east.projection?.sequence, 2)
        XCTAssertEqual(north.projection?.sequence, 2)
        XCTAssertTrue(east.isHost)
        XCTAssertFalse(north.isHost)

        for coordinator in coordinators.values { coordinator.detach() }
    }

    func testHostRecoveryRetriesAndClearsItsStatusAfterSuccess() async throws {
        let room = StallableRoom(peers: peers, hostPlayerID: "north")
        let transports = Dictionary(uniqueKeysWithValues: peers.map { peer in
            (peer.playerID, room.transport(for: peer.playerID))
        })
        let coordinators = Dictionary(uniqueKeysWithValues: peers.map { peer in
            let retryDelay: Duration = peer.playerID == "east"
                ? .milliseconds(1)
                : .milliseconds(250)
            let maximumDelay: Duration = peer.playerID == "east"
                ? .milliseconds(2)
                : .seconds(4)
            return (peer.playerID, RoomOnlineGameCoordinator(
                heartbeat: .disabled,
                hostRecoveryRetryInitialDelay: retryDelay,
                hostRecoveryRetryMaximumDelay: maximumDelay
            ))
        })

        for peer in peers {
            await coordinators[peer.playerID]?.attach(
                transport: try XCTUnwrap(transports[peer.playerID])
            )
        }

        let east = try XCTUnwrap(coordinators["east"])
        let eastTransport = try XCTUnwrap(transports["east"])
        eastTransport.hostRecoveryFailuresRemaining = 2
        room.migrateHost(to: "east", recovery: nil)

        await pump(until: {
            east.state == .connectedAsHost && eastTransport.hostRecoveryAttemptCount == 3
        }, timeout: .seconds(1))

        XCTAssertTrue(east.isHost)
        XCTAssertEqual(east.liveness, .live)
        XCTAssertNil(east.errorText, "A completed recovery must clear its transient recovery banner.")
        XCTAssertEqual(eastTransport.hostRecoveryAttemptCount, 3)

        for coordinator in coordinators.values { coordinator.detach() }
    }

    func testStaleRecoveryCannotReclaimAuthorityAfterDemotion() async throws {
        let room = StallableRoom(peers: peers, hostPlayerID: "north")
        let transports = Dictionary(uniqueKeysWithValues: peers.map { peer in
            (peer.playerID, room.transport(for: peer.playerID))
        })
        let coordinators = Dictionary(uniqueKeysWithValues: peers.map { peer in
            (peer.playerID, RoomOnlineGameCoordinator(heartbeat: .disabled))
        })

        for peer in peers {
            await coordinators[peer.playerID]?.attach(
                transport: try XCTUnwrap(transports[peer.playerID])
            )
        }

        let east = try XCTUnwrap(coordinators["east"])
        let south = try XCTUnwrap(coordinators["south"])
        let eastTransport = try XCTUnwrap(transports["east"])
        eastTransport.suspendStateReports = true

        room.migrateHost(to: "east", recovery: nil)
        await pump(until: {
            east.isHost &&
            east.state == .selectingHost &&
            eastTransport.stateReportAttemptCount == 1
        })

        // The worker commit does not cooperate with task cancellation. Demote
        // east while that await is suspended, then let the stale call return.
        // Its old recovery task must not announce itself or publish afterward.
        room.migrateHost(to: "south", recovery: nil)
        await pump(until: {
            !east.isHost &&
            east.state == .connectedAsClient &&
            south.state == .connectedAsHost
        })
        eastTransport.resumeStateReport()
        await pump(until: { eastTransport.stateReportReturnCount == 1 })
        await Task.yield()

        XCTAssertFalse(east.isHost)
        XCTAssertEqual(east.state, .connectedAsClient)
        XCTAssertEqual(
            eastTransport.seatAssignmentCount,
            0,
            "A cancelled recovery must not advertise stale host authority after its await returns."
        )

        for coordinator in coordinators.values { coordinator.detach() }
    }

    func testClientIgnoresForgedHostMessagesAndStaleProjections() async throws {
        let room = StallableRoom(peers: peers, hostPlayerID: "north")
        let hostTransport = room.transport(for: "north")
        let clientTransport = room.transport(for: "east")
        let southTransport = room.transport(for: "south")

        let host = RoomOnlineGameCoordinator(
            dealSource: ScriptedDealSource(decks: [Deck.standard32]),
            heartbeat: .disabled
        )
        let client = RoomOnlineGameCoordinator(heartbeat: .disabled)
        let south = RoomOnlineGameCoordinator(heartbeat: .disabled)

        await host.attach(transport: hostTransport)
        await client.attach(transport: clientTransport)
        await south.attach(transport: southTransport)

        host.send(.startDeal(dealer: nil, deck: nil))
        await pump(until: { client.projection?.sequence == 1 })

        let tableID = try XCTUnwrap(client.tableID)
        let northPeer = try XCTUnwrap(peers.first { $0.playerID == "north" })
        let southPeer = try XCTUnwrap(peers.first { $0.playerID == "south" })
        let genuine = try XCTUnwrap(client.projection)

        // A seated guest forges the three host-only message kinds at east. The
        // relay routes by recipient, not authority, so only the client's own
        // host-sender check stands in the way of a seat hijack, a fabricated
        // game state, and a fake error banner.
        clientTransport.receive(ReceivedRoomMessage(
            message: .seatAssignment(SeatAssignmentEnvelope(
                tableID: tableID,
                hostPlayerID: "south",
                seats: peers.map(\.playerIdentity),
                rules: .sochi,
                match: .unbounded
            )),
            sender: southPeer
        ))
        var forgedProjection = genuine
        forgedProjection.sequence = 99
        clientTransport.receive(ReceivedRoomMessage(
            message: .projection(ProjectionEnvelope(
                tableID: tableID,
                sequence: 99,
                viewer: "east",
                projection: forgedProjection,
                eventSummaries: ["forged"]
            )),
            sender: southPeer
        ))
        clientTransport.receive(ReceivedRoomMessage(
            message: .hostError(HostErrorEnvelope(
                tableID: tableID,
                sequence: 99,
                recipient: "east",
                clientNonce: nil,
                message: "forged error"
            )),
            sender: southPeer
        ))

        // A genuine action still flows: had the forged assignment rebound the
        // host seat, north's next projection would be rejected; had the forged
        // sequence-99 projection applied, sequence 2 would be dropped as stale.
        let bidder = try currentBidder(in: genuine)
        fixtureLessSend(.bid(player: bidder, call: .pass), from: bidder, host: host, client: client, south: south)
        await pump(until: { client.projection?.sequence == 2 })
        XCTAssertNil(client.errorText, "A forged host error must never surface to the player.")

        // A stale projection from the *real* host (an out-of-order resync
        // response) must not roll the client back. The sentinel host error
        // proves the stale frame was already processed when we assert.
        clientTransport.receive(ReceivedRoomMessage(
            message: .projection(ProjectionEnvelope(
                tableID: tableID,
                sequence: genuine.sequence,
                viewer: "east",
                projection: genuine,
                eventSummaries: []
            )),
            sender: northPeer
        ))
        clientTransport.receive(ReceivedRoomMessage(
            message: .hostError(HostErrorEnvelope(
                tableID: tableID,
                sequence: 2,
                recipient: "east",
                clientNonce: nil,
                message: "sentinel"
            )),
            sender: northPeer
        ))
        await pump(until: { client.errorText == "sentinel" })
        XCTAssertEqual(
            client.projection?.sequence,
            2,
            "An out-of-order older projection must never regress the client's state."
        )

        host.detach()
        client.detach()
        south.detach()
    }

    /// Route an action from whichever coordinator owns the seat, mirroring
    /// `apply(_:from:in:)` for tests that build coordinators without a fixture.
    private func fixtureLessSend(
        _ action: PreferansAction,
        from player: PlayerID,
        host: RoomOnlineGameCoordinator,
        client: RoomOnlineGameCoordinator,
        south: RoomOnlineGameCoordinator
    ) {
        switch player {
        case "north": host.send(action)
        case "east": client.send(action)
        default: south.send(action)
        }
    }

    func testInMemorySessionAutomatesRemotePeersThroughRoomTransport() async throws {
        let inMemoryPeers = peers.map { peer in
            guard peer.playerID != "north" else { return peer }
            return OnlinePeer(
                playerID: peer.playerID,
                accountID: "\(OnlinePeer.botAccountPrefix)\(peer.playerID.rawValue)",
                provider: .dev,
                displayName: peer.displayName
            )
        }
        let session = try InMemoryOnlineGameSession(
            peers: inMemoryPeers,
            localPlayerID: "north",
            hostPlayerID: "north",
            automatedPlayerIDs: ["east", "south"],
            dealSource: ScriptedDealSource(decks: [Deck.standard32]),
            botDelay: .milliseconds(1)
        )
        try await session.start()
        defer { session.stop() }

        session.localCoordinator.send(.startDeal(dealer: nil, deck: nil))
        await pump(until: { session.localCoordinator.projection?.sequence ?? 0 >= 1 })

        let opening = try XCTUnwrap(session.localCoordinator.projection)
        XCTAssertEqual(try currentBidder(in: opening), "north")
        session.localCoordinator.send(.bid(player: "north", call: .pass))

        await pump(
            until: { session.localCoordinator.projection?.sequence ?? 0 >= 4 },
            timeout: .seconds(1)
        )

        let projection = try XCTUnwrap(session.localCoordinator.projection)
        XCTAssertGreaterThanOrEqual(projection.sequence, 4)
        guard case .playing = projection.phase else {
            return XCTFail("Three automated passes should advance the room into all-pass play.")
        }
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
        var preCloseProjection: PlayerGameProjection?

        for _ in 0..<4 {
            guard let action = nextRoomPlayAction(in: fixture) else {
                return XCTFail("Expected a legal card play while driving the first trick.")
            }
            let projectionBeforeAction = host.projection
            try await apply(action.action, from: action.sender, in: fixture, sequence: &sequence)
            if (host.projection?.completedTrickCount ?? 0) > completedBefore {
                preCloseProjection = projectionBeforeAction
                break
            }
        }

        let preClose = try XCTUnwrap(preCloseProjection)
        let authoritative = try XCTUnwrap(host.projection)
        let pending = try XCTUnwrap(host.pendingAdvance)
        let display = try XCTUnwrap(host.displayProjection)

        XCTAssertTrue(authoritative.currentTrick.isEmpty)
        XCTAssertEqual(pending.trickPlays?.count, authoritative.seats.filter(\.isActive).count)
        XCTAssertEqual(display.currentTrick, pending.trickPlays)
        XCTAssertEqual(display.completedTrickCount, completedBefore)
        XCTAssertEqual(pending.phaseOverride, preClose.phase)
        XCTAssertEqual(display.phase, preClose.phase)
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
        trickResultHoldDuration: Duration = .milliseconds(1_400)
    ) async throws -> RoomFixture {
        let room = InMemoryRoom(peers: peers, hostPlayerID: "north")
        let transports = try Dictionary(uniqueKeysWithValues: peers.map { peer in
            (peer.playerID, try room.transport(for: peer.playerID))
        })
        let coordinators: [PlayerID: RoomOnlineGameCoordinator] = Dictionary(uniqueKeysWithValues: peers.map { peer in
            (
                peer.playerID,
                RoomOnlineGameCoordinator(
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
    private(set) var hostPlayerID: PlayerID
    private var recoveryContext: OnlineResumeContext?
    private var transports: [PlayerID: StallableTransport] = [:]

    init(peers: [OnlinePeer], hostPlayerID: PlayerID) {
        self.peers = peers
        self.hostPlayerID = hostPlayerID
    }

    func transport(for playerID: PlayerID) -> StallableTransport {
        let peer = peers.first { $0.playerID == playerID } ?? peers[0]
        let transport = StallableTransport(room: self, localPeer: peer)
        transports[playerID] = transport
        return transport
    }

    fileprivate func deliver(_ message: GameWireMessage, from sender: OnlinePeer, to recipients: [OnlinePeer]) {
        for recipient in recipients where recipient.playerID != sender.playerID {
            transports[recipient.playerID]?.receive(ReceivedRoomMessage(message: message, sender: sender))
        }
    }

    func migrateHost(to playerID: PlayerID, recovery: OnlineResumeContext?) {
        hostPlayerID = playerID
        recoveryContext = recovery
        for transport in transports.values {
            transport.receivePresence()
        }
    }

    fileprivate func currentRecoveryContext() -> OnlineResumeContext? {
        recoveryContext
    }
}

@MainActor
private final class StallableTransport: RoomRealtimeTransport {
    let localPeer: OnlinePeer
    let participants: [OnlinePeer]
    /// While true, the socket is treated as down: sends are recorded but not
    /// delivered, and inbound messages are dropped.
    var isStalled = false
    var suspendStateReports = false
    var hostRecoveryFailuresRemaining = 0
    private(set) var sentMessages: [GameWireMessage] = []
    private(set) var hostRecoveryAttemptCount = 0
    private(set) var stateReportAttemptCount = 0
    private(set) var stateReportReturnCount = 0

    private let room: StallableRoom
    private var continuations: [UUID: AsyncStream<ReceivedRoomMessage>.Continuation] = [:]
    private var participantContinuations: [UUID: AsyncStream<[OnlinePeer]>.Continuation] = [:]
    private var backlog: [ReceivedRoomMessage] = []
    private var stateReportContinuation: CheckedContinuation<Void, Never>?

    init(room: StallableRoom, localPeer: OnlinePeer) {
        self.room = room
        self.localPeer = localPeer
        self.participants = room.peers
    }

    var resyncRequestCount: Int {
        sentMessages.filter { if case .resyncRequest = $0 { return true } else { return false } }.count
    }

    var seatAssignmentCount: Int {
        sentMessages.filter { if case .seatAssignment = $0 { return true } else { return false } }.count
    }

    func chooseHost() async -> OnlinePeer? {
        participants.first { $0.playerID == room.hostPlayerID }
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

    func hostRecoveryContext() async throws -> OnlineResumeContext? {
        hostRecoveryAttemptCount += 1
        if hostRecoveryFailuresRemaining > 0 {
            hostRecoveryFailuresRemaining -= 1
            throw StallableTransportError.recoveryUnavailable
        }
        return room.currentRecoveryContext()
    }

    func reportState(
        status: PreferansGameStatus,
        summary: OnlineStateSummary,
        snapshot: PreferansSnapshot?,
        snapshotSequence: Int
    ) async throws {
        stateReportAttemptCount += 1
        if suspendStateReports {
            await withCheckedContinuation { continuation in
                stateReportContinuation = continuation
            }
        }
        stateReportReturnCount += 1
    }

    func resumeStateReport() {
        suspendStateReports = false
        let continuation = stateReportContinuation
        stateReportContinuation = nil
        continuation?.resume()
    }

    func disconnect() {
        resumeStateReport()
        for continuation in continuations.values { continuation.finish() }
        continuations.removeAll()
        for continuation in participantContinuations.values { continuation.finish() }
        participantContinuations.removeAll()
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

    fileprivate func receivePresence() {
        guard !isStalled else { return }
        for continuation in participantContinuations.values {
            continuation.yield(participants)
        }
    }
}

private enum StallableTransportError: Error {
    case recoveryUnavailable
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
    var blockedReportSequences: Set<Int> = []
    private(set) var events: [String] = []

    private let hostPlayerID: PlayerID
    private var participantContinuations: [UUID: AsyncStream<[OnlinePeer]>.Continuation] = [:]
    private var connectionContinuations: [UUID: AsyncStream<RoomTransportEvent>.Continuation] = [:]

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

    func connectionEvents() -> AsyncStream<RoomTransportEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            connectionContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.connectionContinuations.removeValue(forKey: id) }
            }
        }
    }

    func send(_ message: GameWireMessage, to peers: [OnlinePeer], reliably: Bool) async throws {
        if case let .projection(envelope) = message {
            events.append("projection:\(envelope.sequence)")
        }
    }

    func sendToAll(_ message: GameWireMessage, reliably: Bool) async throws {
        if case .seatAssignment = message {
            events.append("seat-assignment")
        }
    }

    func reportState(
        status: PreferansGameStatus,
        summary: OnlineStateSummary,
        snapshot: PreferansSnapshot?,
        snapshotSequence: Int
    ) async throws {
        events.append("report-attempt:\(snapshotSequence)")
        if blockedReportSequences.contains(snapshotSequence) {
            throw URLError(.networkConnectionLost)
        }
        events.append("report-commit:\(snapshotSequence)")
    }

    func disconnect() {
        for continuation in participantContinuations.values {
            continuation.finish()
        }
        participantContinuations.removeAll()
        for continuation in connectionContinuations.values {
            continuation.finish()
        }
        connectionContinuations.removeAll()
    }

    func simulatePresence(_ peers: [OnlinePeer]) {
        participants = peers
        for continuation in participantContinuations.values {
            continuation.yield(peers)
        }
    }


    func simulateConnectionEvent(_ event: RoomTransportEvent) {
        for continuation in connectionContinuations.values {
            continuation.yield(event)
        }
    }
}
