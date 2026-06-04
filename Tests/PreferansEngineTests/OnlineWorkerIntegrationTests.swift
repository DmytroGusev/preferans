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

        let account = "apple:itest-\(UUID().uuidString.prefix(8))"
        let host = OnlinePeer(playerID: "north", accountID: account, provider: .apple, displayName: "North")
        let bot = OnlinePeer(playerID: "east", accountID: "bot:east", provider: .dev, displayName: "Bot 2")
        let open = OnlinePeer(playerID: "south", accountID: "pending:south", provider: .dev, displayName: "Open")

        let transport = try await CloudflareRoomTransport.createRoom(
            baseURL: baseURL,
            localPeer: host,
            seats: [host, bot, open],
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
        let games = try await directory.fetchMyGames(accountID: account)
        let game = try XCTUnwrap(games.first { $0.roomCode == transport.roomCode })
        XCTAssertEqual(game.status, .playing)
        XCTAssertEqual(game.phase, "bidding")
        XCTAssertEqual(game.youSeat, "north")

        // The opaque blob round-trips back into the exact PreferansSnapshot sent.
        let payload = try await CloudflareRoomTransport.fetchSnapshot(
            baseURL: baseURL,
            roomCode: transport.roomCode,
            playerID: "north"
        )
        XCTAssertEqual(payload.status, .playing)
        XCTAssertEqual(payload.decodedSnapshot, snapshot)

        // Abandon drops the game out of Continue (status flips to abandoned).
        try await CloudflareRoomTransport.abandon(baseURL: baseURL, roomCode: transport.roomCode, playerID: "north")
        let afterAbandon = try await directory.fetchMyGames(accountID: account)
        XCTAssertNil(afterAbandon.first { $0.roomCode == transport.roomCode && $0.status != .abandoned })

        transport.disconnect()
    }
}
