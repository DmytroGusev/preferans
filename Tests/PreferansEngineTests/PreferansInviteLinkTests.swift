import XCTest
@testable import PreferansApp

final class PreferansInviteLinkTests: XCTestCase {
    func testParsesUniversalInviteURL() throws {
        let url = PreferansInviteLink.inviteURL(roomCode: "ab-12")
        XCTAssertEqual(PreferansInviteLink.roomCode(from: url), "AB12")
    }

    func testParsesPastedInviteURLText() {
        XCTAssertEqual(
            PreferansInviteLink.roomCode(from: "https://preferans-room-worker.dmytro-gusev.workers.dev/join/k7-m2?q=1"),
            "K7M2"
        )
    }

    func testParsesPastedInvitePathText() {
        XCTAssertEqual(PreferansInviteLink.roomCode(from: "join/k7-m2"), "K7M2")
        XCTAssertEqual(PreferansInviteLink.roomCode(from: "/join/k7-m2"), "K7M2")
    }

    func testRejectsNonInviteURL() throws {
        let url = try XCTUnwrap(URL(string: "https://preferans-room-worker.ontofractal.workers.dev/support/K7M2Q9"))
        XCTAssertNil(PreferansInviteLink.roomCode(from: url))
    }

    func testParsesAppLinkAndRejectsOldBackendOrLookalikeLinks() {
        XCTAssertEqual(PreferansInviteLink.roomCode(from: "com.mixandmatch.preferans://table/join/K7M2"), "K7M2")
        for value in [
            "https://preferans-room-worker.ontofractal.workers.dev/join/K7M2",
            "https://example.com/join/K7M2",
            "https://preferans-room-worker.dmytro-gusev.workers.dev/join/K7M2/extra",
            "https://user@preferans-room-worker.dmytro-gusev.workers.dev/join/K7M2",
            "AB!CD"
        ] {
            XCTAssertNil(PreferansInviteLink.roomCode(from: value), value)
        }
    }
}
