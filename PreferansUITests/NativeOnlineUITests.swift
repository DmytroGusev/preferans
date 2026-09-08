import Foundation
import XCTest
import PreferansEngine

/// Real native account/room flows against the loopback worker and engine.
/// Run the services described in workers/room-worker/README.md first.
/// Credentials use the app's isolated DEBUG loopback namespace.
@MainActor
final class NativeOnlineUITests: XCTestCase {
    private let baseURL = URL(string: "http://127.0.0.1:8787")!
    private var peerTokens: [String] = []
    private var sockets: [URLSessionWebSocketTask] = []

    override func setUp() async throws {
        // Throw on missing prerequisites so asynchronous tests unwind and clean
        // up immediately; XCTest's abort exception can strand an async tearDown.
        continueAfterFailure = true
        do {
            let health = try await request("GET", "/health")
            guard health["service"] as? String == "preferans-room-worker" else {
                throw XCTSkip("The loopback service is not the Preferans room worker.")
            }
        } catch {
            throw XCTSkip("Native online tests require the local room worker on 127.0.0.1:8787 and engine on 18081.")
        }
    }

    override func tearDown() async throws {
        sockets.forEach { $0.cancel(with: .normalClosure, reason: nil) }
        for token in peerTokens {
            do {
                _ = try await request("DELETE", "/v2/account", token: token)
            } catch {
                XCTFail("Could not delete a loopback QA peer account: \(error.localizedDescription)")
            }
        }
        sockets = []
        peerTokens = []
    }

    func testNativeHostCreatesStartsLeavesAndResumesAfterRelaunch() async throws {
        let app = try launchApp()
        try registerNativeGuest(in: app, name: "QA Native Host")
        print("[native-online] create through the app")
        let create = app.buttons[UIIdentifiers.onlineCreateRoom]
        try reveal(create, in: app)
        create.tap()
        let codeElement = app.staticTexts[UIIdentifiers.onlineRoomCode]
        try require(codeElement.waitForExistence(timeout: 3))
        let code = try XCTUnwrap(codeElement.value as? String)
        XCTAssertEqual(code.count, 6)
        capture(app, "native-host-waiting")
        let start = app.buttons[UIIdentifiers.onlineStartGame]
        XCTAssertFalse(start.isEnabled)

        for (seat, name) in [("east", "QA Peer East"), ("south", "QA Peer South")] {
            let token = try await registerPeer(name)
            let joined = try await request("POST", "/v2/rooms/\(code)/join",
                                           body: ["requestedPlayerID": ["rawValue": seat]], token: token)
            _ = try await connect(joined)
        }
        try require(start.wait(for: \.isEnabled, toEqual: true, timeout: 3))
        capture(app, "native-host-connected")
        start.tap()
        try require(app.staticTexts[UIIdentifiers.phaseTitle].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts[UIIdentifiers.phaseTitle].label, "Bidding")
        let handBefore = handIDs(in: app, seat: "north")
        XCTAssertEqual(handBefore.count, 10)
        capture(app, "native-host-first-auction")

        print("[native-online] leave, relaunch, and resume the same hand")
        try leaveTable(in: app, captureName: "native-host-leave")
        app.terminate()
        app.launch()
        try enterOnline(in: app)
        let resume = app.buttons[UIIdentifiers.onlineGameResume(roomCode: code)]
        try require(resume.waitForExistence(timeout: 3))
        try reveal(resume, in: app)
        capture(app, "native-host-your-games")
        resume.tap()
        try require(app.staticTexts[UIIdentifiers.phaseTitle].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts[UIIdentifiers.phaseTitle].label, "Bidding")
        XCTAssertEqual(handIDs(in: app, seat: "north"), handBefore)
        capture(app, "native-host-resumed")
        try leaveTable(in: app)
        try deleteNativeAccount(in: app)
    }

    func testNativeGuestJoinsAnInviteAndReceivesServerPlay() async throws {
        print("[native-online] create an independent host account")
        let hostToken = try await registerPeer("QA API Host")
        let created = try await request("POST", "/v2/rooms", body: [
            "localPlayerID": ["rawValue": "north"], "maxPlayers": 3,
            "seats": [
                ["playerID": ["rawValue": "north"], "kind": "you"],
                ["playerID": ["rawValue": "east"], "kind": "open"],
                ["playerID": ["rawValue": "south"], "kind": "open"]
            ],
            "rules": try jsonObject(PreferansRules.sochi),
            "match": try jsonObject(MatchSettings(poolTarget: 6))
        ], token: hostToken)
        let hostSocket = try await connect(created)
        let code = try XCTUnwrap(created["roomCode"] as? String)
        let peerToken = try await registerPeer("QA API South")
        let peerRoom = try await request("POST", "/v2/rooms/\(code)/join",
                                        body: ["requestedPlayerID": ["rawValue": "south"]], token: peerToken)
        let peerSocket = try await connect(peerRoom)

        let app = try launchApp()
        try registerNativeGuest(in: app, name: "QA Native Guest")
        let invite = app.textFields[UIIdentifiers.onlineJoinRoomCode]
        try reveal(invite, in: app)
        invite.tap()
        invite.typeText(code + "\n")
        let waiting = app.descendants(matching: .any)[UIIdentifiers.screenWaitingRoom]
        try require(waiting.waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts[UIIdentifiers.onlineRoomCode].value as? String, code)
        try require(app.descendants(matching: .any)[UIIdentifiers.onlineWaitingForHost].exists)
        capture(app, "native-guest-joined")

        // Leaving the waiting room retains the seat and exposes a resume row.
        try leaveTable(in: app, captureName: "native-guest-leave-waiting")
        let resume = app.buttons[UIIdentifiers.onlineGameResume(roomCode: code)]
        try require(resume.waitForExistence(timeout: 3))
        try reveal(resume, in: app)
        resume.tap()
        try require(waiting.waitForExistence(timeout: 3))
        try await send(.startDeal(dealer: nil, deck: nil), actor: "north", room: created,
                       sequence: 0, socket: hostSocket)
        try require(app.staticTexts[UIIdentifiers.phaseTitle].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts[UIIdentifiers.phaseTitle].label, "Bidding")
        XCTAssertEqual(handIDs(in: app, seat: "east").count, 10)
        try require(handIDs(in: app, seat: "north").isEmpty)
        try require(handIDs(in: app, seat: "south").isEmpty)
        capture(app, "native-guest-server-auction")

        // North dealt, so the native east seat opens the auction.
        let pass = app.buttons[UIIdentifiers.bidButton(.pass)]
        try require(pass.waitForExistence(timeout: 3))
        pass.tap()
        try require(pass.waitForNonExistence(timeout: 3))
        try await waitForProjection(sequence: 2, socket: peerSocket)
        capture(app, "native-guest-bid-accepted")
        try await send(.bid(player: PlayerID("south"), call: .pass), actor: "south", room: peerRoom,
                       sequence: 2, socket: peerSocket)
        try await send(.bid(player: PlayerID("north"), call: .pass), actor: "north", room: created,
                       sequence: 3, socket: hostSocket)
        MatchUIRobot(app: app).waitForPhase("Play")
        try require(MatchUIRobot(app: app).playFirstPlayableHandCard(acceptanceTimeout: 1))
        try await waitForProjection(sequence: 5, socket: peerSocket)
        XCTAssertEqual(handIDs(in: app, seat: "east").count, 9)
        capture(app, "native-guest-card-accepted")
        try leaveTable(in: app)
        try deleteNativeAccount(in: app)
    }

    private func launchApp() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.disableUITestAnimations()
        app.launchEnvironment["PREFERANS_ROOM_WORKER_URL"] = baseURL.absoluteString
        app.launchArguments += [UITestFlags.theme, "graphite"]
        app.launch()
        try enterOnline(in: app)
        return app
    }

    private func enterOnline(in app: XCUIApplication) throws {
        let online = app.buttons[UIIdentifiers.lobbyModeOnline]
        try require(online.waitForExistence(timeout: 3))
        online.tap()
    }

    private func registerNativeGuest(in app: XCUIApplication, name: String) throws {
        let guest = app.buttons[UIIdentifiers.onlineRegisterAsGuest]
        if !guest.exists { try deleteNativeAccount(in: app) }
        let field = app.textFields[UIIdentifiers.onlineDisplayNameField]
        try require(field.waitForExistence(timeout: 3))
        field.tap()
        field.typeText(name + "\n")
        guest.tap()
        try require(guest.waitForNonExistence(timeout: 3))
        capture(app, "native-account-registered")
    }

    private func leaveTable(in app: XCUIApplication, captureName: String? = nil) throws {
        app.buttons[UIIdentifiers.buttonLeaveTable].tap()
        let alert = app.alerts.firstMatch
        try require(alert.waitForExistence(timeout: 2))
        try require(alert.buttons["Stay"].exists)
        try require(alert.staticTexts["You can return to this game from Your games in the lobby."].exists)
        if let captureName { capture(app, captureName) }
        alert.buttons["Leave table"].tap()
        try require(app.buttons[UIIdentifiers.lobbySettingsButton].waitForExistence(timeout: 3))
    }

    private func deleteNativeAccount(in app: XCUIApplication) throws {
        print("[native-online] delete the native QA account")
        app.buttons[UIIdentifiers.lobbySettingsButton].tap()
        let delete = app.buttons[UIIdentifiers.onlineDeleteAccount]
        try reveal(delete, in: app)
        delete.tap()
        let confirm = app.alerts.buttons["Delete online account"]
        try require(confirm.waitForExistence(timeout: 2))
        capture(app, "native-delete-confirmation")
        confirm.tap()
        try require(app.staticTexts["No saved account"].waitForExistence(timeout: 3))
        capture(app, "native-account-deleted")
        app.buttons[UIIdentifiers.buttonDismissSheet].tap()
        for _ in 0..<6 where !app.buttons[UIIdentifiers.onlineRegisterAsGuest].isHittable { app.swipeDown() }
        try require(app.buttons[UIIdentifiers.onlineRegisterAsGuest].exists)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) throws {
        for _ in 0..<8 {
            if element.exists && element.isHittable && app.frame.insetBy(dx: 0, dy: 75).contains(element.frame) { return }
            app.swipeUp()
        }
        try require(element.isHittable, "The requested online control must be reachable")
    }

    private func handIDs(in app: XCUIApplication, seat: String) -> Set<String> {
        Set(app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@ AND NOT identifier CONTAINS '.hidden.'",
                        "card.hand.\(seat).")
        ).allElementsBoundByIndex.map(\.identifier))
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        MatchScreenshotRecorder(testCase: self, app: app).capture(name: name, force: true)
    }

    private func require(_ condition: @autoclosure () -> Bool,
                         _ message: String = "Required online state did not appear",
                         file: StaticString = #filePath, line: UInt = #line) throws {
        guard condition() else {
            throw NSError(domain: "NativeOnlineUITests", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "\(message) (\(file):\(line))"])
        }
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }

    private func registerPeer(_ name: String) async throws -> String {
        let account = try await request("POST", "/v2/accounts/guest", body: ["displayName": name])
        let token = try XCTUnwrap(account["sessionToken"] as? String)
        peerTokens.append(token)
        return token
    }

    private func request(_ method: String, _ path: String, body: [String: Any]? = nil,
                         token: String? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: 3)
        request.httpMethod = method
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = try XCTUnwrap(response as? HTTPURLResponse).statusCode
        guard (200..<300).contains(status) else {
            throw NSError(domain: "NativeOnlineUITests", code: status,
                          userInfo: [NSLocalizedDescriptionKey: "\(method) \(path) returned HTTP \(status)"])
        }
        return data.isEmpty ? [:] : (try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:])
    }

    private func connect(_ room: [String: Any]) async throws -> URLSessionWebSocketTask {
        let raw = try XCTUnwrap(room["websocketURL"] as? String)
        let url = try XCTUnwrap(URL(string: raw))
        XCTAssertEqual(url.host, "127.0.0.1")
        let socket = URLSession.shared.webSocketTask(with: url)
        sockets.append(socket)
        socket.resume()
        _ = try await receive(socket)
        return socket
    }

    private func receive(_ socket: URLSessionWebSocketTask) async throws -> [String: Any] {
        let deadline = Task {
            try await Task.sleep(for: .seconds(3))
            socket.cancel(with: .goingAway, reason: nil)
        }
        defer { deadline.cancel() }
        let message: URLSessionWebSocketTask.Message
        do {
            message = try await socket.receive()
        } catch {
            // Foundation errors include the authenticated socket URL. Keep it
            // out of XCTest diagnostics and persisted result bundles.
            throw NSError(domain: "NativeOnlineUITests", code: (error as NSError).code,
                          userInfo: [NSLocalizedDescriptionKey: "The QA peer connection ended before its expected frame"])
        }
        let data: Data
        switch message {
        case .data(let bytes): data = bytes
        case .string(let string): data = Data(string.utf8)
        @unknown default: throw NSError(domain: "NativeOnlineUITests", code: -1)
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func send(_ action: PreferansAction, actor: String, room: [String: Any],
                      sequence: Int, socket: URLSessionWebSocketTask) async throws {
        let nonce = UUID().uuidString.lowercased()
        let envelope: [String: Any] = ["type": "wire", "message": ["clientAction": ["_0": [
            "schemaVersion": PreferansWireSchema.current,
            "tableID": try XCTUnwrap(room["authoritativeTableID"]),
            "actor": ["rawValue": actor], "action": try jsonObject(action),
            "clientNonce": nonce, "baseHostSequence": sequence,
            "sentAt": ISO8601DateFormatter().string(from: Date())
        ]]]]
        let data = try JSONSerialization.data(withJSONObject: envelope)
        do {
            try await socket.send(.data(data))
        } catch {
            throw NSError(domain: "NativeOnlineUITests", code: (error as NSError).code,
                          userInfo: [NSLocalizedDescriptionKey: "Could not send the QA peer action"])
        }
        for _ in 0..<20 {
            let frame = try await receive(socket)
            if frame["type"] as? String == "error" {
                throw NSError(domain: "NativeOnlineUITests", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "Peer action rejected: \(frame["code"] as? String ?? "unknown")"])
            }
            if let receipt = frame["receipt"] as? [String: Any],
               (receipt["clientNonce"] as? String)?.lowercased() == nonce {
                try require(receipt["status"] as? String == "accepted",
                            "Peer action rejected: \(receipt["code"] as? String ?? "unknown")")
                return
            }
        }
        XCTFail("The server did not acknowledge the peer action")
    }

    private func waitForProjection(sequence: Int, socket: URLSessionWebSocketTask) async throws {
        for _ in 0..<20 {
            let frame = try await receive(socket)
            let message = frame["message"] as? [String: Any]
            let payload = message?["projection"] as? [String: Any]
            let envelope = payload?["_0"] as? [String: Any]
            if envelope?["sequence"] as? Int == sequence { return }
        }
        try require(false, "An independent peer did not receive the native player's committed action")
    }
}
