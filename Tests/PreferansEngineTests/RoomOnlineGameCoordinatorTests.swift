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

        try fixture.transports[bidder]?.send(.clientAction(envelope), to: [fixture.hostPeer], reliably: true)
        sequence += 1
        await pump(until: { fixture.allProjectionsAre(at: sequence) })

        try fixture.transports[bidder]?.send(.clientAction(envelope), to: [fixture.hostPeer], reliably: true)
        await pump(until: {
            fixture.coordinators[bidder]?.errorText?.contains("Duplicate action nonce") == true
        })

        XCTAssertEqual(fixture.coordinators["north"]?.projection?.sequence, sequence)
        XCTAssertEqual(fixture.coordinators[bidder]?.projection?.sequence, sequence)
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

    private func makeFixture() async throws -> RoomFixture {
        let room = InMemoryRoom(peers: peers, hostPlayerID: "north")
        let transports = try Dictionary(uniqueKeysWithValues: peers.map { peer in
            (peer.playerID, try room.transport(for: peer.playerID))
        })
        let coordinators = Dictionary(uniqueKeysWithValues: peers.map { peer in
            (
                peer.playerID,
                RoomOnlineGameCoordinator(dealSource: ScriptedDealSource(decks: [Deck.standard32]))
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
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<50 {
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
