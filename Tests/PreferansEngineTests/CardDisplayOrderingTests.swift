import XCTest
@testable import PreferansApp
import PreferansEngine

final class CardDisplayOrderingTests: XCTestCase {
    func testDefaultTableDisplayOrderUsesSpadesDiamondsClubsHeartsWithRanksLowToHigh() {
        let unsorted = [
            Card(.spades, .ace),
            Card(.hearts, .ace),
            Card(.clubs, .seven),
            Card(.diamonds, .ace),
            Card(.spades, .seven),
            Card(.clubs, .ace),
            Card(.diamonds, .seven),
            Card(.hearts, .seven)
        ]

        XCTAssertEqual(
            unsorted.sortedForTableDisplay(),
            [
                Card(.spades, .seven),
                Card(.spades, .ace),
                Card(.diamonds, .seven),
                Card(.diamonds, .ace),
                Card(.clubs, .seven),
                Card(.clubs, .ace),
                Card(.hearts, .seven),
                Card(.hearts, .ace)
            ]
        )
    }

    func testTableDisplayOrderCanUseAlternatingRedBlackPreset() {
        let unsorted = [
            Card(.spades, .ace),
            Card(.hearts, .seven),
            Card(.clubs, .seven),
            Card(.diamonds, .seven)
        ]

        XCTAssertEqual(
            unsorted.sortedForTableDisplay(order: .diamondsClubsHeartsSpades),
            [
                Card(.diamonds, .seven),
                Card(.clubs, .seven),
                Card(.hearts, .seven),
                Card(.spades, .ace)
            ]
        )
    }

    func testProjectedTableDisplayOrderKeepsHiddenCardsAfterKnownCards() {
        let unsorted: [ProjectedCard] = [
            .hidden,
            .known(Card(.spades, .ace)),
            .known(Card(.diamonds, .seven)),
            .hidden,
            .known(Card(.clubs, .seven))
        ]

        XCTAssertEqual(
            unsorted.sortedForTableDisplay(),
            [
                .known(Card(.spades, .ace)),
                .known(Card(.diamonds, .seven)),
                .known(Card(.clubs, .seven)),
                .hidden,
                .hidden
            ]
        )
    }
}
