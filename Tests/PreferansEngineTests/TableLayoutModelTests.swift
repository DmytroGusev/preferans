import XCTest
@testable import PreferansApp
import PreferansEngine

final class TableLayoutModelTests: XCTestCase {
    func testThreeOpponentSlotsStayInUpperThirdWithCenterSeatHighest() {
        let layout = TableLayoutModel(bounds: CGSize(width: 1_000, height: 700))
        let slots = layout.opponentSlots(opponents: [
            seat("east"),
            seat("south"),
            seat("west")
        ])

        XCTAssertEqual(slots.map(\.orientation), [.left, .top, .right])
        XCTAssertEqual(slots.map(\.kind), [.topNarrow, .topNarrow, .topNarrow])
        XCTAssertEqual(slots.map(\.position.x), [0.18, 0.50, 0.82])
        XCTAssertEqual(slots.map(\.position.y), [0.26, 0.10, 0.26])
        assertEqual(layout.playAreaSize, CGSize(width: 860, height: 434))
        assertEqual(layout.playAreaPosition, CGPoint(x: 500, y: 434))
        assertEqual(layout.slotFrameSize(for: slots[0]), CGSize(width: 190, height: 182))
    }

    func testOpenOpponentEarnsLargerSlotAndShrinksPlayArea() {
        let layout = TableLayoutModel(bounds: CGSize(width: 1_000, height: 700))
        let east = seat("east")
        let openSouth = seat("south", hand: [.known(Card(.spades, .ace)), .hidden])
        let west = seat("west")
        let opponents = [east, openSouth, west]
        let slots = layout.opponentSlots(opponents: opponents)

        // The open seat sits at the top-center; its y nudges down so the
        // taller suit-grouped fan clears the screen edge.
        XCTAssertEqual(slots[1].position.y, 0.22, accuracy: 0.001)
        XCTAssertEqual(slots[0].position.y, 0.26, accuracy: 0.001)
        XCTAssertEqual(slots[2].position.y, 0.26, accuracy: 0.001)

        // Open slot frame grows to fit the bigger card size and the
        // ≤4 suit-row stack; hidden slots stay compact.
        assertEqual(layout.slotFrameSize(for: slots[1]), CGSize(width: 280, height: 280))
        assertEqual(layout.slotFrameSize(for: slots[0]), CGSize(width: 190, height: 182))

        // Play area shrinks vertically and drifts down to give the open
        // seat headroom above the trick.
        let play = layout.playArea(for: opponents)
        assertEqual(play.size, CGSize(width: 860, height: 350))
        assertEqual(play.position, CGPoint(x: 500, y: 476))
    }

    func testTrickOffsetsTrackViewerAndOpponentCount() {
        assertEqual(
            TableLayoutModel.trickOffset(for: "north", viewer: "north", opponents: ["east", "south"]),
            CGSize(width: 0, height: 51.8)
        )
        assertEqual(
            TableLayoutModel.trickOffset(for: "east", viewer: "north", opponents: ["east", "south"]),
            CGSize(width: -57.2, height: -33.3)
        )
        assertEqual(
            TableLayoutModel.trickOffset(for: "south", viewer: "north", opponents: ["east", "south"]),
            CGSize(width: 57.2, height: -33.3)
        )
    }

    private func seat(_ player: PlayerID, hand: [ProjectedCard] = []) -> SeatProjection {
        SeatProjection(
            player: player,
            displayName: player.rawValue,
            isActive: true,
            isDealer: false,
            isCurrentActor: false,
            role: .active,
            hand: hand,
            trickCount: 0
        )
    }

    private func assertEqual(_ actual: CGPoint, _ expected: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.001, file: file, line: line)
    }

    private func assertEqual(_ actual: CGSize, _ expected: CGSize, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.001, file: file, line: line)
    }
}
