import XCTest
@testable import PreferansApp
import PreferansEngine

private struct PublicTableStub: PublicTableServing {
    var page: PublicTablePage
    func fetchTables(sessionToken: String, offset: Int) async throws -> PublicTablePage { page }
}

@MainActor
final class PublicTableLobbyTests: XCTestCase {
    func testCatalogDecodesWithoutPrivateAccountDataAndClearsWhenSignedOut() async throws {
        let data = Data("""
        {"tables":[{"roomCode":"PUBLIC","variant":"odesa","poolTarget":33,"poolClosure":"individualWithAmericanAid",
        "maxPlayers":3,"players":[{"displayName":"Host","ready":true,"connected":true}],"openSeats":2,
        "status":"lobby","createdAt":"2026-10-02T12:00:00Z"}],"nextOffset":null}
        """.utf8)
        let page = try JSONDecoder().decode(PublicTablePage.self, from: data)
        let lobby = PublicTableLobby(directory: PublicTableStub(page: page))
        await lobby.refresh(sessionToken: "test-session")
        XCTAssertEqual(lobby.tables.count, 1)
        XCTAssertTrue(lobby.tables[0].canJoin)
        XCTAssertEqual(lobby.tables[0].settings.displayedPoolTarget(playerCount: 3), 11)
        XCTAssertEqual(OnlineTableSettings(variant: "wien", poolTarget: 33, poolClosure: "tableTotal")
            .displayedPoolTarget(playerCount: 3), 33)
        await lobby.refresh(sessionToken: nil)
        XCTAssertTrue(lobby.tables.isEmpty)
        XCTAssertNil(lobby.nextOffset)
    }

    func testRunningAndFullTablesCannotBeJoined() {
        let table = PublicOnlineTable(roomCode: "TABLE1", variant: "wien", poolTarget: 33, poolClosure: "tableTotal",
            maxPlayers: 3, players: [], openSeats: 0, status: .lobby, createdAt: "2026-10-02T12:00:00Z")
        XCTAssertFalse(table.canJoin)
        var running = table
        running.openSeats = 1
        running.status = .playing
        XCTAssertFalse(running.canJoin)
    }
}
