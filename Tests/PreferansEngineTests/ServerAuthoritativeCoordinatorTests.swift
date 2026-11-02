import XCTest
@testable import PreferansApp
@testable import PreferansEngine

@MainActor
final class ServerAuthoritativeCoordinatorTests: XCTestCase {
    func testHostAddsBotWithoutAutoStartingAndPublicBotsNeedNoReadyTap() async throws {
        let tableID = UUID()
        let host = OnlinePeer(playerID: "north", accountID: "guest:north", provider: .guest, displayName: "Host")
        let guest = OnlinePeer(playerID: "east", accountID: "guest:east", provider: .guest, displayName: "Friend")
        let open = OnlinePeer(playerID: "south", accountID: "pending:south", provider: .dev, displayName: "Open seat")
        let transport = ServerAuthoritativeTestTransport(localPeer: host, participants: [host, guest, open], tableID: tableID)
        transport.isPublicTable = true
        transport.readyPlayerIDs = ["north", "east"]
        let coordinator = ServerGameCoordinator()
        await coordinator.attach(transport: transport)
        let engine = try PreferansEngine(players: ["north", "east", "south"], rules: .sochi, firstDealer: "north")
        let projection = PlayerProjectionBuilder.projection(for: "north", tableID: tableID, sequence: 0,
            engine: engine, identities: [host, guest, open].map(\.playerIdentity), policy: .online)
        transport.receive(.init(message: .projection(.init(tableID: tableID, sequence: 0, viewer: "north",
            projection: projection, eventSummaries: [])), sender: host, authority: .server))
        await eventually { coordinator.canManageBotSeats }
        await coordinator.configureBotSeat("south", difficulty: .expert)
        XCTAssertEqual(coordinator.rosterSeats.last?.botDifficulty, .expert)
        XCTAssertTrue(coordinator.rosterSeats.last?.occupancy.isBot == true)
        XCTAssertFalse(coordinator.isUpdatingBotSeats)
        XCTAssertFalse(coordinator.canHostStart, "Roster changes require humans to confirm Ready again")
        XCTAssertTrue(transport.sentMessages.isEmpty, "Adding a bot must not start the game")
        transport.rejectsBotEdits = true
        await coordinator.configureBotSeat("south", difficulty: .casual)
        XCTAssertNotNil(coordinator.errorText)
        XCTAssertFalse(coordinator.isUpdatingBotSeats, "Failure must release the editing controls")
        XCTAssertEqual(coordinator.rosterSeats.last?.botDifficulty, .expert)
        transport.rejectsBotEdits = false
        transport.readyPlayerIDs = ["north", "east"]
        transport.receiveConnectionEvent(.connected)
        await eventually { coordinator.canHostStart }
        await coordinator.configureBotSeat("south", difficulty: nil)
        XCTAssertEqual(coordinator.rosterSeats.last?.occupancy, .openWaiting)
        XCTAssertFalse(coordinator.canHostStart)
        coordinator.detach()
    }

    func testNonHostCannotEditBotSeats() async {
        let host = OnlinePeer(playerID: "north", accountID: "guest:north", provider: .guest, displayName: "Host")
        let guest = OnlinePeer(playerID: "east", accountID: "guest:east", provider: .guest, displayName: "Friend")
        let transport = ServerAuthoritativeTestTransport(localPeer: guest, participants: [host, guest], tableID: UUID())
        let coordinator = ServerGameCoordinator()
        await coordinator.attach(transport: transport)
        XCTAssertFalse(coordinator.canManageBotSeats)
        await coordinator.configureBotSeat("south", difficulty: .casual)
        XCTAssertEqual(transport.botEdits, 0)
        coordinator.detach()
    }

    func testPendingMoveSurvivesClientRestartAndReceiptClearsIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = OnlineCommandOutbox(directory: directory)
        let table = UUID()
        let peer = OnlinePeer(playerID: "north", accountID: "guest:north", provider: .guest, displayName: "North")
        let command = ClientActionEnvelope(tableID: table, actor: "north",
            action: .startDeal(dealer: nil, deck: nil), baseHostSequence: 0)
        try outbox.store(command, account: peer.accountID)
        let transport = ServerAuthoritativeTestTransport(localPeer: peer, participants: [peer], tableID: table)
        let coordinator = ServerGameCoordinator(outbox: outbox)
        await coordinator.attach(transport: transport)
        XCTAssertTrue(coordinator.isSubmitting)
        transport.receiveConnectionEvent(.connected)
        await eventually { transport.sentMessages.count == 1 }
        XCTAssertEqual(transport.sentMessages.first, .clientAction(command), "Retry preserves the exact ID and payload")
        transport.receiveConnectionEvent(.commandReceipt(.init(tableID: table, clientNonce: command.clientNonce,
            sequence: 1, status: .accepted)))
        await eventually { !coordinator.isSubmitting }
        XCTAssertNil(try outbox.load(table: table, account: peer.accountID))
        coordinator.detach()
    }

    func testUnrelatedReceiptCannotClearPendingMoveAndTakeoverStopsSubmission() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = OnlineCommandOutbox(directory: directory)
        let table = UUID()
        let peer = OnlinePeer(playerID: "north", accountID: "guest:north", provider: .guest, displayName: "North")
        let command = ClientActionEnvelope(tableID: table, actor: "north",
            action: .startDeal(dealer: nil, deck: nil), baseHostSequence: 0)
        try outbox.store(command, account: peer.accountID)
        let transport = ServerAuthoritativeTestTransport(localPeer: peer, participants: [peer], tableID: table)
        let coordinator = ServerGameCoordinator(outbox: outbox)
        await coordinator.attach(transport: transport)
        transport.receiveConnectionEvent(.commandReceipt(.init(tableID: table, clientNonce: UUID(),
            sequence: 1, status: .accepted)))
        transport.receiveConnectionEvent(.seatTakenOver)
        await eventually { coordinator.transportStatus == .seatTakenOver }
        XCTAssertTrue(coordinator.isSubmitting)
        XCTAssertEqual(try outbox.load(table: table, account: peer.accountID), command)
        XCTAssertTrue(transport.sentMessages.isEmpty)
        XCTAssertNil(try outbox.load(table: table, account: "another-account"))
        coordinator.detach()
    }

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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let coordinator = ServerGameCoordinator(outbox: OnlineCommandOutbox(directory: directory))

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

    func testSupersededRejectionIsSilentButAJudgedRejectionIsShown() {
        let command = ClientActionEnvelope(tableID: UUID(), actor: "east",
            action: .startDeal(dealer: nil, deck: nil), baseHostSequence: 7)
        func receipt(_ sequence: Int, _ status: OnlineCommandReceipt.Status) -> OnlineCommandReceipt {
            .init(tableID: command.tableID, clientNonce: command.clientNonce, sequence: sequence,
                  status: status, code: "engine_rejected_command", message: "Stale command sequence.")
        }
        XCTAssertNil(ServerGameCoordinator.rejectionMessage(for: receipt(8, .rejected), basedOn: command),
                     "Another player's Next deal won the race; the newer projection already shows it.")
        XCTAssertEqual(ServerGameCoordinator.rejectionMessage(for: receipt(7, .rejected), basedOn: command),
                       "Stale command sequence.")
        XCTAssertNil(ServerGameCoordinator.rejectionMessage(for: receipt(8, .accepted), basedOn: command))
    }

    func testLostSeatStopsSubmissionAndDropsTheSavedMove() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outbox = OnlineCommandOutbox(directory: directory)
        let table = UUID()
        let peer = OnlinePeer(playerID: "north", accountID: "guest:north", provider: .guest, displayName: "North")
        let command = ClientActionEnvelope(tableID: table, actor: "north",
            action: .startDeal(dealer: nil, deck: nil), baseHostSequence: 0)
        try outbox.store(command, account: peer.accountID)
        let transport = ServerAuthoritativeTestTransport(localPeer: peer, participants: [peer], tableID: table)
        let coordinator = ServerGameCoordinator(outbox: outbox)
        await coordinator.attach(transport: transport)
        XCTAssertTrue(coordinator.isSubmitting)
        transport.receiveConnectionEvent(.seatLost("You left this table."))
        await eventually { coordinator.transportStatus == .disconnected }
        XCTAssertFalse(coordinator.isSubmitting)
        XCTAssertEqual(coordinator.errorText, "You left this table.")
        XCTAssertNil(try outbox.load(table: table, account: peer.accountID))
        coordinator.detach()
    }

    func testOnlyPermanentDisconnectsStopReconnecting() {
        let terminal: [(Int, Int?)] = [(4010, nil), (4011, nil), (1006, 401), (1006, 403), (1006, 404), (1006, 410)]
        for (code, status) in terminal {
            XCTAssertNotNil(CloudflareRoomTransport.terminalDisconnectMessage(closeCode: code, httpStatus: status),
                            "close \(code), HTTP \(String(describing: status))")
        }
        let transient: [(Int, Int?)] = [(1006, nil), (1001, 101), (1011, 101), (1006, 429), (1006, 500), (1006, 503), (4009, nil)]
        for (code, status) in transient {
            XCTAssertNil(CloudflareRoomTransport.terminalDisconnectMessage(closeCode: code, httpStatus: status),
                         "close \(code), HTTP \(String(describing: status))")
        }
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
    var participants: [OnlinePeer]
    var isPublicTable = false
    var readyPlayerIDs: Set<PlayerID> = []
    var botEdits = 0
    var rejectsBotEdits = false
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

    func configureBotSeat(_ player: PlayerID, difficulty: BotDifficulty?) async throws {
        if rejectsBotEdits { throw URLError(.notConnectedToInternet) }
        botEdits += 1
        let index = participants.firstIndex { $0.playerID == player }!
        participants[index] = OnlinePeer(playerID: player,
            accountID: "\(difficulty == nil ? "pending" : "bot"):\(player.rawValue)",
            provider: .dev, displayName: "Bot", botDifficulty: difficulty)
        readyPlayerIDs = []
    }

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
