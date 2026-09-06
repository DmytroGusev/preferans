import XCTest
@testable import PreferansApp
@testable import PreferansEngine

@MainActor
final class ServerAuthoritativeCoordinatorTests: XCTestCase {
    func testCloudAuthorityNeverCreatesAClientHostAndAcceptsServerProjection() async throws {
        let tableID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let peers = ["north", "east", "south"].map {
            OnlinePeer(
                playerID: $0,
                accountID: "guest:\($0.rawValue)",
                provider: .guest,
                displayName: $0.rawValue.capitalized
            )
        }
        let transport = ServerAuthoritativeTestTransport(
            localPeer: peers[0],
            participants: peers,
            tableID: tableID
        )
        let coordinator = ServerGameCoordinator()

        await coordinator.attach(transport: transport)

        XCTAssertEqual(coordinator.tableID, tableID)
        XCTAssertTrue(coordinator.isHost, "The creator may manage the lobby, but is not game authority.")
        XCTAssertNil(transport.reportedSnapshot)
        XCTAssertTrue(transport.sentMessages.isEmpty, "Attach must not emit hello or client-authored state.")

        let engine = try PreferansEngine(
            players: peers.map(\.playerID),
            rules: .sochi,
            firstDealer: "north"
        )
        let projection = PlayerProjectionBuilder.projection(
            for: "north",
            tableID: tableID,
            sequence: 0,
            engine: engine,
            identities: peers.map(\.playerIdentity),
            policy: .online
        )
        transport.receive(ReceivedRoomMessage(
            message: .projection(ProjectionEnvelope(
                tableID: tableID,
                sequence: 0,
                viewer: "north",
                projection: projection,
                eventSummaries: []
            )),
            // Deliberately not the lobby manager: explicit server authority,
            // rather than a disguised peer identity, is what grants trust.
            sender: peers[2],
            authority: .server
        ))
        await eventually { coordinator.projection != nil }

        XCTAssertTrue(coordinator.startFirstDeal())
        await eventually {
            transport.sentMessages.contains { if case .clientAction = $0 { true } else { false } }
        }
        XCTAssertNil(transport.reportedSnapshot)
        XCTAssertFalse(transport.sentMessages.contains { message in
            switch message {
            case .seatAssignment, .hello: true
            default: false
            }
        })

        transport.receiveConnectionEvent(.serverError("That bid is no longer legal."))
        await eventually { coordinator.errorText == "That bid is no longer legal." }
        coordinator.detach()
    }

    private func eventually(
        _ predicate: @escaping @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 where !predicate() {
            await Task.yield()
        }
        XCTAssertTrue(predicate(), file: file, line: line)
    }
}

@MainActor
private final class ServerAuthoritativeTestTransport: RoomRealtimeTransport {
    let localPeer: OnlinePeer
    let participants: [OnlinePeer]
    let authoritativeTableID: UUID?
    let isServerAuthoritative = true
    var connectedPlayerIDs: Set<PlayerID> { Set(participants.map(\.playerID)) }
    private(set) var sentMessages: [GameWireMessage] = []
    private(set) var reportedSnapshot: PreferansSnapshot?
    private var continuation: AsyncStream<ReceivedRoomMessage>.Continuation?
    private var connectionContinuation: AsyncStream<RoomTransportEvent>.Continuation?

    init(localPeer: OnlinePeer, participants: [OnlinePeer], tableID: UUID) {
        self.localPeer = localPeer
        self.participants = participants
        self.authoritativeTableID = tableID
    }

    func chooseHost() async -> OnlinePeer? { participants.first }

    func messages() -> AsyncStream<ReceivedRoomMessage> {
        AsyncStream { continuation = $0 }
    }

    func connectionEvents() -> AsyncStream<RoomTransportEvent> {
        AsyncStream { connectionContinuation = $0 }
    }

    func send(_ message: GameWireMessage, to peers: [OnlinePeer], reliably: Bool) async throws {
        sentMessages.append(message)
    }

    func sendToAll(_ message: GameWireMessage, reliably: Bool) async throws {
        sentMessages.append(message)
    }

    func reportState(
        status: PreferansGameStatus,
        summary: OnlineStateSummary,
        snapshot: PreferansSnapshot?,
        snapshotSequence: Int
    ) async throws {
        reportedSnapshot = snapshot
    }

    func disconnect() {
        continuation?.finish()
        connectionContinuation?.finish()
    }

    func receive(_ message: ReceivedRoomMessage) { continuation?.yield(message) }
    func receiveConnectionEvent(_ event: RoomTransportEvent) { connectionContinuation?.yield(event) }
}
