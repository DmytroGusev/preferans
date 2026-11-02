import XCTest
@testable import PreferansApp
import PreferansEngine

private final class CapturingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var healthHandler: ((URLRequest) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (status, data): (Int, Data)
            if request.url?.path == "/health" {
                (status, data) = try Self.healthHandler?(request) ?? (200, Data(#"{"ok":true,"service":"preferans-room-worker","accountSchemaVersion":2,"roomSchemaVersion":4}"#.utf8))
            } else {
                (status, data) = try handler(request)
            }
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["content-type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class OnlineTransportSecurityTests: XCTestCase {
    private var session: URLSession!
    private let baseURL = URL(string: "https://worker.example.test")!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CapturingURLProtocol.self]
        session = URLSession(configuration: configuration)
    }

    override func tearDown() {
        CapturingURLProtocol.handler = nil
        CapturingURLProtocol.healthHandler = nil
        session.invalidateAndCancel()
        session = nil
        super.tearDown()
    }

    @MainActor
    func testLegacyServerIsRejectedBeforeCreateOrJoinMutatesAnything() async throws {
        var mutations = 0
        CapturingURLProtocol.handler = { _ in mutations += 1; return (500, Data()) }
        CapturingURLProtocol.healthHandler = { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "authorization"))
            XCTAssertEqual(request.timeoutInterval, 8)
            return (200, Data(#"{"ok":true,"service":"preferans-room-worker","accountSchemaVersion":2,"roomSchemaVersion":3}"#.utf8))
        }
        let host = OnlinePeer(playerID: "north", accountID: "guest:server-id", provider: .guest, displayName: "Ada")
        for isJoin in [false, true] {
            do {
                if isJoin {
                    _ = try await CloudflareRoomTransport.joinRoom(baseURL: baseURL, roomCode: "ABC123", localPeer: host, accountSessionToken: "secret", session: session)
                } else {
                    _ = try await CloudflareRoomTransport.createRoom(baseURL: baseURL, localPeer: host, seats: [host], accountSessionToken: "secret", session: session)
                }
                XCTFail("Legacy servers cannot open protocol-4 tables")
            } catch CloudflareRoomTransportError.incompatibleServer {} catch { XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(mutations, 0)
    }

    @MainActor
    func testGuestRegistrationUsesV2AndAcceptsOnlyServerIssuedIdentity() async throws {
        var captured: URLRequest?
        var capturedBody: Data?
        CapturingURLProtocol.handler = { request in
            captured = request
            capturedBody = Self.bodyData(request)
            return (201, Data(#"{"account":{"schemaVersion":2,"accountID":"guest:server-id","provider":"guest","displayName":"Ada"},"sessionToken":"pref2.account.secret"}"#.utf8))
        }

        let result = try await CloudflareAccountClient(baseURL: baseURL, session: session)
            .registerGuest(displayName: "Ada")

        XCTAssertEqual(captured?.url?.path, "/v2/accounts/guest")
        XCTAssertNil(captured?.value(forHTTPHeaderField: "authorization"))
        let body = try XCTUnwrap(capturedBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object.keys.sorted(), ["displayName"])
        XCTAssertEqual(result.account.accountID, "guest:server-id")
        XCTAssertEqual(result.account.provider, .guest)
        XCTAssertEqual(result.account.schemaVersion, 2)
    }

    @MainActor
    func testRoomMutationRejectsAnIncompatibleSchemaVersion() async throws {
        CapturingURLProtocol.handler = { _ in
            (201, Data(#"{"schemaVersion":1,"roomCode":"ABC123","hostPlayerID":{"rawValue":"north"},"hostEpoch":1,"peers":[],"maxPlayers":3,"createdAt":"2026-07-31T00:00:00Z","updatedAt":"2026-07-31T00:00:00Z","relaySequence":0,"status":"lobby","websocketURL":"wss://worker.example.test/v1/rooms/ABC123/socket?playerID=north&seatToken=seat","seatToken":"seat"}"#.utf8))
        }
        let host = OnlinePeer(playerID: "north", accountID: "guest:server-id", provider: .guest, displayName: "Ada")

        do {
            _ = try await CloudflareRoomTransport.createRoom(
                baseURL: baseURL,
                localPeer: host,
                seats: [host],
                accountSessionToken: "pref2.account.secret",
                maxPlayers: 3,
                session: session
            )
            XCTFail("An incompatible room schema must be rejected.")
        } catch {
            XCTAssertEqual(
                (error as? CloudflareRoomTransportError)?.errorDescription,
                "Room server returned an incompatible room version."
            )
        }
    }

    @MainActor
    func testRoomMutationRejectsAnInvalidRelaySequence() async throws {
        CapturingURLProtocol.handler = { _ in
            (201, Data(#"{"schemaVersion":4,"roomCode":"ABC123","hostPlayerID":{"rawValue":"north"},"hostEpoch":1,"peers":[{"playerID":{"rawValue":"north"},"accountID":"guest:server-id","provider":"guest","displayName":"Ada"}],"maxPlayers":3,"createdAt":"2026-07-31T00:00:00Z","updatedAt":"2026-07-31T00:00:00Z","relaySequence":-1,"websocketURL":"wss://worker.example.test/v2/rooms/ABC123/socket?playerID=north&seatToken=seat","seatToken":"seat"}"#.utf8))
        }
        let host = OnlinePeer(playerID: "north", accountID: "guest:server-id", provider: .guest, displayName: "Ada")

        do {
            _ = try await CloudflareRoomTransport.createRoom(
                baseURL: baseURL,
                localPeer: host,
                seats: [host],
                accountSessionToken: "pref2.account.secret",
                maxPlayers: 3,
                session: session
            )
            XCTFail("A negative relay sequence must be rejected.")
        } catch {
            XCTAssertEqual(
                (error as? CloudflareRoomTransportError)?.errorDescription,
                "Room server returned an invalid relay sequence."
            )
        }
    }

    @MainActor
    func testRoomMutationRejectsAResponseWithoutTheCallersSeat() async throws {
        CapturingURLProtocol.handler = { _ in
            (201, Data(#"{"schemaVersion":4,"roomCode":"ABC123","hostPlayerID":{"rawValue":"north"},"hostEpoch":1,"peers":[],"maxPlayers":3,"createdAt":"2026-07-31T00:00:00Z","updatedAt":"2026-07-31T00:00:00Z","relaySequence":0,"status":"lobby","websocketURL":"wss://worker.example.test/v2/rooms/ABC123/socket?playerID=north&seatToken=seat","seatToken":"seat"}"#.utf8))
        }
        let host = OnlinePeer(playerID: "north", accountID: "guest:server-id", provider: .guest, displayName: "Ada")

        do {
            _ = try await CloudflareRoomTransport.createRoom(
                baseURL: baseURL,
                localPeer: host,
                seats: [host],
                accountSessionToken: "pref2.account.secret",
                maxPlayers: 3,
                session: session
            )
            XCTFail("A room response without the caller's seat must be rejected.")
        } catch {
            XCTAssertEqual(
                (error as? CloudflareRoomTransportError)?.errorDescription,
                "Room server did not return the caller's seat."
            )
        }
    }

    @MainActor
    func testPublicCreationRejectsLegacyServerSilentlyCreatingPrivateRoom() async throws {
        CapturingURLProtocol.handler = { _ in
            (201, Data(#"{"schemaVersion":4,"roomCode":"ABC123","hostPlayerID":{"rawValue":"north"},"hostEpoch":1,"peers":[],"maxPlayers":3,"createdAt":"2026-07-31T00:00:00Z","updatedAt":"2026-07-31T00:00:00Z","relaySequence":0,"status":"lobby"}"#.utf8))
        }
        let host = OnlinePeer(playerID: "north", accountID: "guest:server-id", provider: .guest, displayName: "Ada")
        do {
            _ = try await CloudflareRoomTransport.createRoom(
                baseURL: baseURL, localPeer: host, seats: [host],
                accountSessionToken: "pref2.account.secret", maxPlayers: 3,
                visibility: .publicTable, session: session
            )
            XCTFail("Public room creation must not silently downgrade to private.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Public tables are not available"))
        }
    }

    @MainActor
    func testPublicDirectoryExplainsMissingProductionDeployment() async throws {
        CapturingURLProtocol.handler = { _ in (404, Data()) }
        do {
            _ = try await CloudflarePublicTableDirectory(baseURL: baseURL, session: session)
                .fetchTables(sessionToken: "pref2.account.secret")
            XCTFail("An old server does not support public discovery.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("room code"))
        }
    }

    @MainActor
    func testAccountDeletionUsesAuthenticatedV2Endpoint() async throws {
        var captured: URLRequest?
        CapturingURLProtocol.handler = { request in
            captured = request
            return (204, Data())
        }

        try await CloudflareAccountClient(baseURL: baseURL, session: session)
            .deleteAccount(sessionToken: "pref2.account.secret")

        XCTAssertEqual(captured?.httpMethod, "DELETE")
        XCTAssertEqual(captured?.url?.path, "/v2/account")
        XCTAssertNil(captured?.httpBody)
        XCTAssertEqual(
            captured?.value(forHTTPHeaderField: "authorization"),
            "Bearer pref2.account.secret"
        )
    }

    @MainActor
    func testGameLibraryDerivesAccountFromBearerWithoutAccountQuery() async throws {
        var captured: URLRequest?
        CapturingURLProtocol.handler = { request in
            captured = request
            return (200, Data(#"{"games":[]}"#.utf8))
        }

        let games = try await CloudflareGameDirectory(baseURL: baseURL, session: session)
            .fetchMyGames(sessionToken: "pref2.account.secret")

        XCTAssertTrue(games.isEmpty)
        XCTAssertEqual(captured?.url?.path, "/v2/my-games")
        XCTAssertNil(captured?.url?.query)
        XCTAssertEqual(
            captured?.value(forHTTPHeaderField: "authorization"),
            "Bearer pref2.account.secret"
        )
    }

    @MainActor
    func testCreateRoomSendsSeatIntentButNoClientDeclaredHumanIdentity() async throws {
        var captured: URLRequest?
        var capturedBody: Data?
        CapturingURLProtocol.handler = { request in
            captured = request
            capturedBody = Self.bodyData(request)
            return (201, Data(#"{"schemaVersion":4,"roomCode":"ABC123","hostPlayerID":{"rawValue":"north"},"hostEpoch":1,"peers":[{"playerID":{"rawValue":"north"},"accountID":"guest:server-id","provider":"guest","displayName":"Ada"},{"playerID":{"rawValue":"east"},"accountID":"bot:east","provider":"dev","displayName":"Bot 2"},{"playerID":{"rawValue":"south"},"accountID":"pending:south","provider":"dev","displayName":"Open seat"}],"maxPlayers":3,"createdAt":"2026-07-31T00:00:00Z","updatedAt":"2026-07-31T00:00:00Z","relaySequence":0,"websocketURL":"wss://worker.example.test/v2/rooms/ABC123/socket?playerID=north&seatToken=seat","seatToken":"seat"}"#.utf8))
        }
        let host = OnlinePeer(playerID: "north", accountID: "guest:server-id", provider: .guest, displayName: "Ada")
        let bot = OnlinePeer(playerID: "east", accountID: "bot:east", provider: .dev, displayName: "Bot 2")
        let open = OnlinePeer(playerID: "south", accountID: "pending:south", provider: .dev, displayName: "Open seat")

        let transport = try await CloudflareRoomTransport.createRoom(
            baseURL: baseURL,
            localPeer: host,
            seats: [host, bot, open],
            accountSessionToken: "pref2.account.secret",
            maxPlayers: 3,
            session: session
        )
        defer { transport.disconnect() }

        XCTAssertEqual(captured?.url?.path, "/v2/rooms")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "authorization"), "Bearer pref2.account.secret")
        let body = try XCTUnwrap(capturedBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(object["localPeer"])
        let encoded = String(decoding: body, as: UTF8.self)
        XCTAssertFalse(encoded.contains("guest:server-id"))
        XCTAssertFalse(encoded.contains("Ada"))
        let seats = try XCTUnwrap(object["seats"] as? [[String: Any]])
        XCTAssertEqual(seats.compactMap { $0["kind"] as? String }, ["you", "bot", "open"])
        XCTAssertEqual(transport.localPeer.accountID, "guest:server-id")
    }

    @MainActor
    func testClientAuthoredStateReportsAreDisabled() async throws {
        var stateRequest: URLRequest?
        var stateBody: Data?
        let roomJSON = Data(#"{"schemaVersion":4,"roomCode":"ABC123","hostPlayerID":{"rawValue":"north"},"hostEpoch":1,"peers":[{"playerID":{"rawValue":"north"},"accountID":"guest:server-id","provider":"guest","displayName":"Ada"},{"playerID":{"rawValue":"east"},"accountID":"bot:east","provider":"dev","displayName":"Bot 2"},{"playerID":{"rawValue":"south"},"accountID":"bot:south","provider":"dev","displayName":"Bot 3"}],"maxPlayers":3,"createdAt":"2026-07-31T00:00:00Z","updatedAt":"2026-07-31T00:00:00Z","relaySequence":0,"websocketURL":"wss://worker.example.test/v2/rooms/ABC123/socket?playerID=north&seatToken=rotated-seat","seatToken":"rotated-seat"}"#.utf8)
        CapturingURLProtocol.handler = { request in
            if request.url?.path.hasSuffix("/state") == true {
                stateRequest = request
                stateBody = Self.bodyData(request)
                return (200, roomJSON)
            }
            return (201, roomJSON)
        }
        let host = OnlinePeer(playerID: "north", accountID: "guest:server-id", provider: .guest, displayName: "Ada")
        let east = OnlinePeer(playerID: "east", accountID: "bot:east", provider: .dev, displayName: "Bot 2")
        let south = OnlinePeer(playerID: "south", accountID: "bot:south", provider: .dev, displayName: "Bot 3")
        let transport = try await CloudflareRoomTransport.createRoom(
            baseURL: baseURL,
            localPeer: host,
            seats: [host, east, south],
            accountSessionToken: "pref2.account.secret",
            maxPlayers: 3,
            session: session
        )
        defer { transport.disconnect() }

        do {
            try await transport.reportState(
                status: .lobby,
                summary: OnlineStateSummary(lastSequence: 0, phase: "waiting"),
                snapshot: nil,
                snapshotSequence: 0
            )
            XCTFail("A schema-v3 client must not upload game state.")
        } catch {
            XCTAssertEqual(
                (error as? CloudflareRoomTransportError)?.errorDescription,
                "Online game state is owned by the server."
            )
        }
        XCTAssertNil(stateRequest)
        XCTAssertNil(stateBody)
    }

    @MainActor
    func testBotSeatMutationSendsSeatProofSelectedStrengthAndExplicitNullRemoval() async throws {
        let host = OnlinePeer(playerID: "north", accountID: "guest:server-id", provider: .guest, displayName: "Host")
        let open = OnlinePeer(playerID: "east", accountID: "pending:east", provider: .dev, displayName: "Open seat")
        var captured: URLRequest?
        var body: Data?
        let room = Data(#"{"schemaVersion":4,"roomCode":"ABC123","hostPlayerID":{"rawValue":"north"},"hostEpoch":1,"peers":[{"playerID":{"rawValue":"north"},"accountID":"guest:server-id","provider":"guest","displayName":"Host"},{"playerID":{"rawValue":"east"},"accountID":"bot:east","provider":"dev","displayName":"Bot 2","botDifficulty":"expert"},{"playerID":{"rawValue":"south"},"accountID":"pending:south","provider":"dev","displayName":"Open seat"}],"maxPlayers":3,"createdAt":"2026-11-02T00:00:00Z","updatedAt":"2026-11-02T00:00:00Z","relaySequence":0,"websocketURL":"wss://worker.example.test/v2/rooms/ABC123/socket?playerID=north&seatToken=seat","seatToken":"seat"}"#.utf8)
        CapturingURLProtocol.handler = { request in
            captured = request
            body = Self.bodyData(request)
            return (200, room)
        }
        let transport = try await CloudflareRoomTransport.createRoom(baseURL: baseURL, localPeer: host,
            seats: [host, open, .init(playerID: "south", accountID: "pending:south", provider: .dev, displayName: "Open seat")],
            accountSessionToken: "pref2.account.secret", maxPlayers: 3, session: session)
        defer { transport.disconnect() }
        try await transport.configureBotSeat("east", difficulty: .expert)
        XCTAssertEqual(captured?.url?.path, "/v2/rooms/ABC123/seats/bot")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "authorization"), "Bearer pref2.account.secret")
        let added = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any])
        XCTAssertEqual(added["seatToken"] as? String, "seat")
        XCTAssertEqual((added["playerID"] as? [String: String])?["rawValue"], "north")
        XCTAssertEqual((added["targetPlayerID"] as? [String: String])?["rawValue"], "east")
        XCTAssertEqual(added["difficulty"] as? String, "expert")
        XCTAssertNil(added["accountID"])
        XCTAssertEqual(transport.participants[1].botDifficulty, .expert)
        try await transport.configureBotSeat("east", difficulty: nil)
        let removed = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(body)) as? [String: Any])
        XCTAssertTrue(removed["difficulty"] is NSNull)
    }

    private static func bodyData(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
