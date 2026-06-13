import PreferansApp
import PreferansEngine
import XCTest

final class ActivityLogFeedTests: XCTestCase {
    func testActivityEntriesUseDisplayNamesAndRedactExchangeCards() {
        let events: [PreferansEvent] = [
            .dealStarted(dealer: "north", activePlayers: ["north", "east", "south"]),
            .talonExchanged(
                declarer: "east",
                talon: [Card(.hearts, .ace), Card(.spades, .seven)],
                discard: [Card(.clubs, .king), Card(.diamonds, .queen)]
            )
        ]
        let names: [PlayerID: String] = [
            "north": "Alice",
            "east": "Bob",
            "south": "Cara"
        ]

        let entries = ActivityLogFeed.entries(from: events) { names[$0] ?? $0.rawValue }
        let rendered = entries
            .map { [$0.title, $0.detail].compactMap(\.self).joined(separator: " ") }
            .joined(separator: "\n")

        XCTAssertTrue(rendered.contains("Alice deals"))
        XCTAssertTrue(rendered.contains("Bob took the prikup"))
        XCTAssertTrue(rendered.contains("Discard hidden"))
        XCTAssertFalse(rendered.contains("east"))
        XCTAssertFalse(rendered.contains("A♥"))
        XCTAssertFalse(rendered.contains("7♠"))
        XCTAssertFalse(rendered.contains("K♣"))
        XCTAssertFalse(rendered.contains("Q♦"))
    }

    func testSanitizedSummariesDoNotUseDebugEventDescriptions() {
        let summaries = ActivityLogFeed.summaries(for: [
            .talonExchanged(
                declarer: "east",
                talon: [Card(.hearts, .ace), Card(.spades, .seven)],
                discard: [Card(.clubs, .king), Card(.diamonds, .queen)]
            )
        ])

        XCTAssertEqual(summaries, ["east took the prikup · Discard hidden"])
        XCTAssertFalse(summaries[0].contains("talonExchanged"))
        XCTAssertFalse(summaries[0].contains("discard:"))
        XCTAssertFalse(summaries[0].contains("A♥"))
    }
}
