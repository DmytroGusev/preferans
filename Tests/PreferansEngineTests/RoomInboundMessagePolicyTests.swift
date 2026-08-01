import XCTest
@testable import PreferansApp
@testable import PreferansEngine

final class RoomInboundMessagePolicyTests: AppTestCase {
    private let tableID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let host = OnlinePeer(
        playerID: "north",
        accountID: "dev:north",
        provider: .dev,
        displayName: "North"
    )
    private let guest = OnlinePeer(
        playerID: "south",
        accountID: "dev:south",
        provider: .dev,
        displayName: "South"
    )

    func testElectedHostAuthenticationRejectsLocalHostAndOtherSeats() {
        XCTAssertTrue(RoomInboundMessagePolicy.isFromElectedHost(
            host,
            localIsHost: false,
            electedHost: host.playerID
        ))
        XCTAssertFalse(RoomInboundMessagePolicy.isFromElectedHost(
            guest,
            localIsHost: false,
            electedHost: host.playerID
        ))
        XCTAssertFalse(RoomInboundMessagePolicy.isFromElectedHost(
            host,
            localIsHost: true,
            electedHost: host.playerID
        ))
    }

    func testSeatAssignmentBindsDeclaredHostAndRequiresUniqueLocalSeat() {
        let seats = identities()
        let valid = SeatAssignmentEnvelope(
            tableID: tableID,
            hostPlayerID: host.playerID,
            seats: seats,
            rules: .sochi
        )
        XCTAssertTrue(RoomInboundMessagePolicy.acceptsSeatAssignment(
            valid,
            sender: host,
            localPlayer: "east"
        ))

        var delegated = valid
        delegated.hostPlayerID = guest.playerID
        XCTAssertFalse(RoomInboundMessagePolicy.acceptsSeatAssignment(
            delegated,
            sender: host,
            localPlayer: "east"
        ))

        var duplicate = valid
        duplicate.seats.append(seats[0])
        XCTAssertFalse(RoomInboundMessagePolicy.acceptsSeatAssignment(
            duplicate,
            sender: host,
            localPlayer: "east"
        ))

        var missingLocal = valid
        missingLocal.seats.removeAll { $0.playerID == "east" }
        XCTAssertFalse(RoomInboundMessagePolicy.acceptsSeatAssignment(
            missingLocal,
            sender: host,
            localPlayer: "east"
        ))
    }

    func testProjectionDecisionSeparatesAdvanceRefreshAndStaleFrames() throws {
        let projection = try makeProjection(sequence: 5)
        let envelope = ProjectionEnvelope(
            tableID: tableID,
            sequence: 5,
            viewer: "east",
            projection: projection,
            eventSummaries: ["event"]
        )

        XCTAssertEqual(decision(envelope, currentTable: tableID, sequence: 4), .advance)
        XCTAssertEqual(decision(envelope, currentTable: tableID, sequence: 5), .refresh)
        XCTAssertEqual(decision(envelope, currentTable: tableID, sequence: 6), .reject)
        XCTAssertEqual(decision(envelope, currentTable: UUID(), sequence: 99), .reject)
        XCTAssertEqual(decision(envelope, currentTable: nil, sequence: nil), .reject)
    }

    func testProjectionDecisionRejectsInconsistentEnvelopeMetadata() throws {
        let projection = try makeProjection(sequence: 5)
        var envelope = ProjectionEnvelope(
            tableID: tableID,
            sequence: 5,
            viewer: "east",
            projection: projection,
            eventSummaries: []
        )

        envelope.sequence = 6
        XCTAssertEqual(decision(envelope), .reject)
        envelope.sequence = 5
        envelope.tableID = UUID()
        XCTAssertEqual(decision(envelope), .reject)
        envelope.tableID = tableID
        envelope.viewer = "south"
        XCTAssertEqual(decision(envelope), .reject)
        envelope.viewer = "east"
        envelope.projection.viewer = "south"
        XCTAssertEqual(decision(envelope), .reject)
    }

    func testErrorsAndResyncRequestsStayBoundToTableAndSender() {
        let error = HostErrorEnvelope(
            tableID: tableID,
            sequence: 3,
            recipient: "east",
            clientNonce: nil,
            message: "Nope"
        )
        XCTAssertTrue(RoomInboundMessagePolicy.acceptsHostError(
            error,
            localPlayer: "east",
            currentTable: tableID
        ))
        XCTAssertFalse(RoomInboundMessagePolicy.acceptsHostError(
            error,
            localPlayer: "south",
            currentTable: tableID
        ))
        XCTAssertFalse(RoomInboundMessagePolicy.acceptsHostError(
            error,
            localPlayer: "east",
            currentTable: UUID()
        ))

        let request = ResyncRequestEnvelope(
            tableID: tableID,
            requester: guest.playerID,
            lastSeenSequence: 2
        )
        XCTAssertTrue(RoomInboundMessagePolicy.acceptsResyncRequest(
            request,
            sender: guest,
            currentTable: tableID
        ))
        XCTAssertFalse(RoomInboundMessagePolicy.acceptsResyncRequest(
            request,
            sender: host,
            currentTable: tableID
        ))
        XCTAssertFalse(RoomInboundMessagePolicy.acceptsResyncRequest(
            request,
            sender: guest,
            currentTable: UUID()
        ))
    }

    func testPingRequiresExactOptionalTableIdentity() {
        XCTAssertTrue(RoomInboundMessagePolicy.acceptsPing(
            PingEnvelope(tableID: tableID),
            currentTable: tableID
        ))
        XCTAssertTrue(RoomInboundMessagePolicy.acceptsPing(
            PingEnvelope(tableID: nil),
            currentTable: nil
        ))
        XCTAssertFalse(RoomInboundMessagePolicy.acceptsPing(
            PingEnvelope(tableID: UUID()),
            currentTable: tableID
        ))
        XCTAssertFalse(RoomInboundMessagePolicy.acceptsPing(
            PingEnvelope(tableID: nil),
            currentTable: tableID
        ))
    }

    private func decision(
        _ envelope: ProjectionEnvelope,
        currentTable: UUID? = nil,
        sequence: Int? = nil
    ) -> RoomInboundMessagePolicy.ProjectionDecision {
        RoomInboundMessagePolicy.projectionDecision(
            for: envelope,
            localPlayer: "east",
            currentTable: currentTable,
            currentSequence: sequence
        )
    }

    private func makeProjection(sequence: Int) throws -> PlayerGameProjection {
        var engine = try PreferansEngine(
            players: ["north", "east", "south"],
            rules: .sochi,
            firstDealer: "south"
        )
        _ = try engine.startDeal(deck: Deck.standard32)
        return PlayerProjectionBuilder.projection(
            for: "east",
            tableID: tableID,
            sequence: sequence,
            engine: engine,
            identities: identities(),
            policy: .online
        )
    }

    private func identities() -> [PlayerIdentity] {
        ["north", "east", "south"].map { player in
            PlayerIdentity(
                playerID: player,
                gamePlayerID: "dev:\(player.rawValue)",
                displayName: player.rawValue.capitalized
            )
        }
    }
}
