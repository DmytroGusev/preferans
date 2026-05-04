import XCTest
@testable import PreferansApp

final class PreferansInviteLinkTests: XCTestCase {
    func testParsesUniversalInviteURL() throws {
        let url = try XCTUnwrap(URL(string: "https://preferans-room-worker.ontofractal.workers.dev/join/ab-12"))
        XCTAssertEqual(PreferansInviteLink.roomCode(from: url), "AB12")
    }

    func testRejectsNonInviteURL() throws {
        let url = try XCTUnwrap(URL(string: "https://preferans-room-worker.ontofractal.workers.dev/support/K7M2Q9"))
        XCTAssertNil(PreferansInviteLink.roomCode(from: url))
    }
}
