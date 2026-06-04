import XCTest
@testable import PreferansApp
@testable import PreferansEngine

/// A canned directory so the library VM can be exercised without a worker.
private struct StubDirectory: OnlineGameDirectory {
    var games: [OnlineGameSummary] = []
    var shouldFail = false

    func fetchMyGames(accountID: String) async throws -> [OnlineGameSummary] {
        if shouldFail {
            throw CloudflareRoomTransportError.serverError("offline")
        }
        return games
    }
}

@MainActor
final class OnlineGameLibraryTests: XCTestCase {
    func testSplitsInProgressFromFinishedAndHidesAbandoned() async throws {
        let library = OnlineGameLibrary(directory: StubDirectory(games: [
            summary("PLAY01", status: .playing, updatedAt: "2026-06-04T10:00:00.000Z"),
            summary("DONE01", status: .finished, updatedAt: "2026-06-04T09:00:00.000Z"),
            summary("LOBBY1", status: .lobby, updatedAt: "2026-06-04T08:00:00.000Z"),
            summary("GONE01", status: .abandoned, updatedAt: "2026-06-04T07:00:00.000Z")
        ]))

        await library.refresh(accountID: "apple:north")

        // Continue = playing + lobby (worker order preserved); History = finished;
        // abandoned games surface nowhere.
        XCTAssertEqual(library.inProgress.map(\.roomCode), ["PLAY01", "LOBBY1"])
        XCTAssertEqual(library.finished.map(\.roomCode), ["DONE01"])
        XCTAssertTrue(library.hasLoaded)
        XCTAssertNil(library.loadError)
    }

    func testNilAccountClearsWithoutAFetch() async throws {
        let library = OnlineGameLibrary(directory: StubDirectory(games: [
            summary("PLAY01", status: .playing, updatedAt: "2026-06-04T10:00:00.000Z")
        ]))

        await library.refresh(accountID: nil)

        XCTAssertTrue(library.isEmpty)
        XCTAssertTrue(library.hasLoaded)
        XCTAssertNil(library.loadError)
    }

    func testFetchFailureSurfacesAnError() async throws {
        let library = OnlineGameLibrary(directory: StubDirectory(shouldFail: true))

        await library.refresh(accountID: "apple:north")

        XCTAssertNotNil(library.loadError)
        XCTAssertTrue(library.hasLoaded)
    }

    func testRemoveLocallyDropsARoomFromBothLists() async throws {
        let library = OnlineGameLibrary(directory: StubDirectory(games: [
            summary("PLAY01", status: .playing, updatedAt: "2026-06-04T10:00:00.000Z"),
            summary("DONE01", status: .finished, updatedAt: "2026-06-04T09:00:00.000Z")
        ]))
        await library.refresh(accountID: "apple:north")

        library.removeLocally(roomCode: "PLAY01")
        XCTAssertEqual(library.inProgress.map(\.roomCode), [])
        XCTAssertEqual(library.finished.map(\.roomCode), ["DONE01"])
    }

    /// Locks the wire contract with the worker's `/my-games` payload, including
    /// the `{rawValue:}` player IDs and the nested result.
    func testDecodesWorkerMyGamesPayload() throws {
        let json = Data("""
        {
          "roomCode": "ABC123",
          "hostPlayerID": { "rawValue": "north" },
          "status": "finished",
          "maxPlayers": 3,
          "peers": [
            { "playerID": { "rawValue": "north" }, "accountID": "apple:north", "provider": "apple", "displayName": "North" },
            { "playerID": { "rawValue": "east" }, "accountID": "bot:east", "provider": "dev", "displayName": "Bot 2" }
          ],
          "youSeat": { "rawValue": "north" },
          "variant": "odesa",
          "lastSequence": 42,
          "result": { "winner": { "rawValue": "north" }, "finalScores": { "north": 6, "east": 2 } },
          "createdAt": "2026-06-04T08:00:00.000Z",
          "updatedAt": "2026-06-04T10:00:00.000Z"
        }
        """.utf8)

        let game = try PreferansJSONCoder.decoder.decode(OnlineGameSummary.self, from: json)

        XCTAssertEqual(game.roomCode, "ABC123")
        XCTAssertEqual(game.status, .finished)
        XCTAssertEqual(game.youSeat, "north")
        XCTAssertEqual(game.result?.winner, "north")
        XCTAssertEqual(game.result?.finalScores?["east"], 2)
        XCTAssertEqual(game.winnerName, "North")
        // The bot seat is excluded from "opponents" (humans you played against).
        XCTAssertEqual(game.opponents.map(\.playerID), [])
        XCTAssertEqual(game.botCount, 1)
    }

    // MARK: - Fixtures

    private func summary(
        _ roomCode: String,
        status: PreferansGameStatus,
        updatedAt: String,
        youSeat: PlayerID = "north"
    ) -> OnlineGameSummary {
        OnlineGameSummary(
            roomCode: roomCode,
            hostPlayerID: "north",
            status: status,
            maxPlayers: 3,
            peers: [
                OnlinePeer(playerID: "north", accountID: "apple:north", provider: .apple, displayName: "North"),
                OnlinePeer(playerID: "east", accountID: "apple:east", provider: .apple, displayName: "East"),
                OnlinePeer(playerID: "south", accountID: "bot:south", provider: .dev, displayName: "Bot 3")
            ],
            youSeat: youSeat,
            variant: "odesa",
            phase: "bidding",
            dealNumber: 1,
            lastSequence: 4,
            result: status == .finished
                ? OnlineGameResult(winner: "north", finalScores: ["north": 6, "east": 2, "south": 1])
                : nil,
            createdAt: updatedAt,
            updatedAt: updatedAt
        )
    }
}
