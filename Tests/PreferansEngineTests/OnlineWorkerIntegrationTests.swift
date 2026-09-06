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

    func testCreateRejectsClientStateAndKeepsPrivateStateOffTheWorkerAPI() async throws {
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

        XCTAssertNotNil(transport.authoritativeTableID)
        do {
            try await transport.reportState(
                status: .playing,
                summary: OnlineStateSummary(variant: "odesa", lastSequence: 1, phase: "bidding", dealNumber: 1),
                snapshot: nil,
                snapshotSequence: 1
            )
            XCTFail("A client must never be able to report authoritative state.")
        } catch let error as CloudflareRoomTransportError {
            guard case .serverError = error else {
                return XCTFail("Expected client state reporting to be disabled, got \(error).")
            }
        }

        // The server-created lobby appears in the creator's library. A rejected
        // client state report cannot move it into playing.
        let directory = CloudflareGameDirectory(baseURL: baseURL)
        let games = try await directory.fetchMyGames(sessionToken: sessionToken)
        let game = try XCTUnwrap(games.first { $0.roomCode == transport.roomCode })
        XCTAssertEqual(game.status, .lobby)
        XCTAssertEqual(game.youSeat, "north")

        // The old snapshot boundary is gone. Reconnects receive only their
        // seat-redacted projection over the socket.
        var snapshotRequest = URLRequest(
            url: baseURL
                .appendingPathComponent("v2")
                .appendingPathComponent("rooms")
                .appendingPathComponent(transport.roomCode)
                .appendingPathComponent("snapshot")
        )
        snapshotRequest.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "authorization")
        let (_, snapshotResponse) = try await URLSession.shared.data(for: snapshotRequest)
        XCTAssertEqual((snapshotResponse as? HTTPURLResponse)?.statusCode, 410)

        var unauthenticated = URLRequest(url: baseURL.appendingPathComponent("v2").appendingPathComponent("my-games"))
        unauthenticated.httpMethod = "GET"
        let (_, unauthenticatedResponse) = try await URLSession.shared.data(for: unauthenticated)
        XCTAssertEqual((unauthenticatedResponse as? HTTPURLResponse)?.statusCode, 401)

        // Rejoining the same seat represents opening the table on a newer
        // device. The room token rotates and the old device immediately loses
        // room access even though its account bearer remains valid.
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

    func testDisconnectedLobbyManagerMigratesWithoutEngineAuthority() async throws {
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

        let recoveryContext = try await eastTransport.hostRecoveryContext()
        XCTAssertNil(recoveryContext)

        do {
            try await eastTransport.reportState(
                status: .playing,
                summary: OnlineStateSummary(lastSequence: 2, phase: "bidding", dealNumber: 1),
                snapshot: nil,
                snapshotSequence: 2
            )
            XCTFail("A lobby-manager migration must not grant engine authority.")
        } catch let error as CloudflareRoomTransportError {
            guard case .serverError = error else {
                return XCTFail("Expected client state reporting to stay disabled, got \(error).")
            }
        }

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
