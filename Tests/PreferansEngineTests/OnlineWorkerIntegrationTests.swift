import XCTest
@testable import PreferansApp
@testable import PreferansEngine

/// Live cross-stack contract test: the Swift client talks to a running room
/// worker. Skipped unless `PREFERANS_WORKER_URL` points at one (e.g. a local
/// `wrangler dev`), so the normal test run stays hermetic.
@MainActor
final class OnlineWorkerIntegrationTests: XCTestCase {
    private var baseURL: URL? {
        ProcessInfo.processInfo.environment["PREFERANS_WORKER_URL"].flatMap { URL(string: $0) }
    }

    func testCreateReportListAndResumeSnapshotRoundTrip() async throws {
        guard let baseURL else {
            throw XCTSkip("Set PREFERANS_WORKER_URL to exercise the live worker.")
        }

        let registration = try await CloudflareAccountClient(baseURL: baseURL)
            .registerGuest(displayName: "North")
        let account = registration.account
        let sessionToken = registration.sessionToken
        let host = OnlinePeer(
            playerID: "north",
            accountID: account.accountID,
            provider: account.provider,
            displayName: account.displayName
        )
        let bot = OnlinePeer(playerID: "east", accountID: "bot:east", provider: .dev, displayName: "Bot 2")
        let open = OnlinePeer(playerID: "south", accountID: "pending:south", provider: .dev, displayName: "Open")

        let transport = try await CloudflareRoomTransport.createRoom(
            baseURL: baseURL,
            localPeer: host,
            seats: [host, bot, open],
            accountSessionToken: sessionToken,
            maxPlayers: 3
        )

        // Build a representative mid-deal engine and push its snapshot.
        var engine = try PreferansEngine(players: ["north", "east", "south"], rules: .sochi, firstDealer: "south")
        _ = try engine.startDeal(deck: Deck.standard32)
        let snapshot = engine.snapshot
        try await transport.reportState(
            status: .playing,
            summary: OnlineStateSummary(variant: "odesa", lastSequence: 1, phase: "bidding", dealNumber: 1),
            snapshot: snapshot,
            snapshotSequence: 1
        )

        // The host's library lists the game with the reported progress.
        let directory = CloudflareGameDirectory(baseURL: baseURL)
        let games = try await directory.fetchMyGames(sessionToken: sessionToken)
        let game = try XCTUnwrap(games.first { $0.roomCode == transport.roomCode })
        XCTAssertEqual(game.status, .playing)
        XCTAssertEqual(game.phase, "bidding")
        XCTAssertEqual(game.youSeat, "north")

        // The opaque blob round-trips back into the exact PreferansSnapshot sent.
        let payload = try await CloudflareRoomTransport.fetchSnapshot(
            baseURL: baseURL,
            roomCode: transport.roomCode,
            playerID: "north",
            seatToken: try XCTUnwrap(transport.seatToken),
            accountSessionToken: sessionToken
        )
        XCTAssertEqual(payload.status, .playing)
        XCTAssertEqual(payload.decodedSnapshot, snapshot)

        // A stolen room token is insufficient without the account session that
        // owns the seat: both layers are checked by the v2 snapshot boundary.
        let intruder = try await CloudflareAccountClient(baseURL: baseURL)
            .registerGuest(displayName: "Intruder")
        do {
            _ = try await CloudflareRoomTransport.fetchSnapshot(
                baseURL: baseURL,
                roomCode: transport.roomCode,
                playerID: "north",
                seatToken: try XCTUnwrap(transport.seatToken),
                accountSessionToken: intruder.sessionToken
            )
            XCTFail("A different account must not use a stolen seat token.")
        } catch let error as CloudflareRoomTransportError {
            guard case .serverError = error else {
                return XCTFail("Expected a server authorization error, got \(error).")
            }
        }

        var unauthenticated = URLRequest(url: baseURL.appendingPathComponent("v2").appendingPathComponent("my-games"))
        unauthenticated.httpMethod = "GET"
        let (_, unauthenticatedResponse) = try await URLSession.shared.data(for: unauthenticated)
        XCTAssertEqual((unauthenticatedResponse as? HTTPURLResponse)?.statusCode, 401)

        // Rejoining the same seat represents opening the table on a newer
        // device. The room token rotates: the old device immediately loses
        // snapshot and host-state authority even though its account bearer is
        // still a valid account session.
        let oldSocketDrain = Task { for await _ in transport.messages() {} }
        defer { oldSocketDrain.cancel() }
        let oldSocketConnected = await eventually {
            transport.latestConnectionEvent == .connected
        }
        XCTAssertTrue(oldSocketConnected)
        let oldSeatToken = try XCTUnwrap(transport.seatToken)
        let takeover = try await CloudflareRoomTransport.joinRoom(
            baseURL: baseURL,
            roomCode: transport.roomCode,
            localPeer: host,
            accountSessionToken: sessionToken
        )
        let takeoverSocketDrain = Task { for await _ in takeover.messages() {} }
        defer { takeoverSocketDrain.cancel() }
        let newSeatToken = try XCTUnwrap(takeover.seatToken)
        XCTAssertNotEqual(newSeatToken, oldSeatToken)
        let takeoverConnected = await eventually {
            takeover.latestConnectionEvent == .connected &&
            transport.latestConnectionEvent == .seatTakenOver
        }
        XCTAssertTrue(takeoverConnected)
        do {
            _ = try await CloudflareRoomTransport.fetchSnapshot(
                baseURL: baseURL,
                roomCode: transport.roomCode,
                playerID: "north",
                seatToken: oldSeatToken,
                accountSessionToken: sessionToken
            )
            XCTFail("The older device credential must be revoked on takeover.")
        } catch let error as CloudflareRoomTransportError {
            guard case .serverError = error else {
                return XCTFail("Expected a room authorization error, got \(error).")
            }
        }
        do {
            try await transport.reportState(
                status: .playing,
                summary: OnlineStateSummary(lastSequence: 2, phase: "bidding", dealNumber: 1),
                snapshot: snapshot,
                snapshotSequence: 2
            )
            XCTFail("A stale device must not retain host-state authority.")
        } catch let error as CloudflareRoomTransportError {
            guard case .serverError = error else {
                return XCTFail("Expected a host authorization error, got \(error).")
            }
        }

        // Abandon drops the game out of Continue (status flips to abandoned).
        try await CloudflareRoomTransport.abandon(
            baseURL: baseURL,
            roomCode: transport.roomCode,
            playerID: "north",
            seatToken: newSeatToken,
            accountSessionToken: sessionToken
        )
        let afterAbandon = try await directory.fetchMyGames(sessionToken: sessionToken)
        XCTAssertNil(afterAbandon.first { $0.roomCode == transport.roomCode && $0.status != .abandoned })

        transport.disconnect()
        takeover.disconnect()
    }

    func testAccountDeletionRevokesSessionAndScrubsLobbySeat() async throws {
        guard let baseURL else {
            throw XCTSkip("Set PREFERANS_WORKER_URL to exercise the live worker.")
        }

        let client = CloudflareAccountClient(baseURL: baseURL)
        let registration = try await client.registerGuest(displayName: "Delete me")
        let account = registration.account
        let host = OnlinePeer(
            playerID: "north",
            accountID: account.accountID,
            provider: account.provider,
            displayName: account.displayName
        )
        let transport = try await CloudflareRoomTransport.createRoom(
            baseURL: baseURL,
            localPeer: host,
            seats: [
                host,
                OnlinePeer(playerID: "east", accountID: "bot:east", provider: .dev, displayName: "Bot 2"),
                OnlinePeer(playerID: "south", accountID: "pending:south", provider: .dev, displayName: "Open")
            ],
            accountSessionToken: registration.sessionToken,
            maxPlayers: 3
        )
        defer { transport.disconnect() }

        try await client.deleteAccount(sessionToken: registration.sessionToken)

        do {
            _ = try await CloudflareGameDirectory(baseURL: baseURL)
                .fetchMyGames(sessionToken: registration.sessionToken)
            XCTFail("A deleted account session must be revoked.")
        } catch let error as CloudflareRoomTransportError {
            guard case .serverError = error else {
                return XCTFail("Expected an account authorization error, got \(error).")
            }
        }

        let summaryURL = baseURL
            .appendingPathComponent("v2")
            .appendingPathComponent("rooms")
            .appendingPathComponent(transport.roomCode)
        let (summaryData, summaryResponse) = try await URLSession.shared.data(from: summaryURL)
        XCTAssertEqual((summaryResponse as? HTTPURLResponse)?.statusCode, 200)
        let summary = try PreferansJSONCoder.decoder.decode(CloudflareRoomSummary.self, from: summaryData)
        let north = try XCTUnwrap(summary.peers.first { $0.playerID == "north" })
        XCTAssertEqual(north.accountID, "pending:north")
        XCTAssertEqual(north.displayName, "Open seat")
        XCTAssertNotEqual(north.accountID, account.accountID)
    }

    func testDisconnectedHostMigratesToAConnectedSeatAndKeepsTheSnapshot() async throws {
        guard let baseURL else {
            throw XCTSkip("Set PREFERANS_WORKER_URL to exercise the live worker.")
        }

        let northRegistration = try await CloudflareAccountClient(baseURL: baseURL)
            .registerGuest(displayName: "North migration")
        let eastRegistration = try await CloudflareAccountClient(baseURL: baseURL)
            .registerGuest(displayName: "East migration")
        let north = OnlinePeer(
            playerID: "north",
            accountID: northRegistration.account.accountID,
            provider: .guest,
            displayName: northRegistration.account.displayName
        )
        let openEast = OnlinePeer(
            playerID: "east",
            accountID: "pending:east",
            provider: .dev,
            displayName: "Open"
        )
        let botSouth = OnlinePeer(
            playerID: "south",
            accountID: "bot:south",
            provider: .dev,
            displayName: "Bot 3"
        )
        let northTransport = try await CloudflareRoomTransport.createRoom(
            baseURL: baseURL,
            localPeer: north,
            seats: [north, openEast, botSouth],
            accountSessionToken: northRegistration.sessionToken,
            maxPlayers: 3
        )
        let eastIntent = OnlinePeer(
            playerID: "east",
            accountID: eastRegistration.account.accountID,
            provider: .guest,
            displayName: eastRegistration.account.displayName
        )
        let eastTransport = try await CloudflareRoomTransport.joinRoom(
            baseURL: baseURL,
            roomCode: northTransport.roomCode,
            localPeer: eastIntent,
            accountSessionToken: eastRegistration.sessionToken
        )

        var engine = try PreferansEngine(players: ["north", "east", "south"], rules: .sochi, firstDealer: "south")
        _ = try engine.startDeal(deck: Deck.standard32)
        let snapshot = engine.snapshot
        try await northTransport.reportState(
            status: .playing,
            summary: OnlineStateSummary(lastSequence: 1, phase: "bidding", dealNumber: 1),
            snapshot: snapshot,
            snapshotSequence: 1
        )

        let northDrain = Task { for await _ in northTransport.messages() {} }
        let eastDrain = Task { for await _ in eastTransport.messages() {} }
        defer {
            northDrain.cancel()
            eastDrain.cancel()
            northTransport.disconnect()
            eastTransport.disconnect()
        }

        let bothConnected = await eventually {
            northTransport.latestConnectionEvent == .connected &&
            eastTransport.latestConnectionEvent == .connected
        }
        XCTAssertTrue(bothConnected)
        XCTAssertEqual(eastTransport.hostPlayerID, "north")
        let initialEpoch = eastTransport.hostEpoch

        northTransport.disconnect()
        let migrated = await eventually {
            eastTransport.hostPlayerID == "east" && eastTransport.hostEpoch > initialEpoch
        }
        XCTAssertTrue(migrated)

        let recoveredContext = try await eastTransport.hostRecoveryContext()
        let recovery = try XCTUnwrap(recoveredContext)
        XCTAssertEqual(recovery.sequence, 1)
        XCTAssertEqual(recovery.snapshot, snapshot)

        do {
            try await northTransport.reportState(
                status: .playing,
                summary: OnlineStateSummary(lastSequence: 2, phase: "bidding", dealNumber: 1),
                snapshot: snapshot,
                snapshotSequence: 2
            )
            XCTFail("The disconnected former host must lose state authority.")
        } catch let error as CloudflareRoomTransportError {
            guard case .serverError = error else {
                return XCTFail("Expected a host authorization error, got \(error).")
            }
        }

        // The successor can immediately commit the recovered state.
        try await eastTransport.reportState(
            status: .playing,
            summary: OnlineStateSummary(lastSequence: 1, phase: "bidding", dealNumber: 1),
            snapshot: recovery.snapshot,
            snapshotSequence: recovery.sequence
        )
        try await CloudflareRoomTransport.abandon(
            baseURL: baseURL,
            roomCode: eastTransport.roomCode,
            playerID: "east",
            seatToken: try XCTUnwrap(eastTransport.seatToken),
            accountSessionToken: eastRegistration.sessionToken
        )
    }

    private func eventually(
        attempts: Int = 200,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<attempts {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
