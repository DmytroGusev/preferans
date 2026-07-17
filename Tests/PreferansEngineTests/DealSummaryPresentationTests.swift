import XCTest
@testable import PreferansApp
import PreferansEngine

final class DealSummaryPresentationTests: XCTestCase {
    func testDeclarerIsDerivedForContractResults() {
        let contract = GameContract(6, .suit(.spades))

        XCTAssertEqual(
            DealSummaryPresentation.declarer(
                in: .game(declarer: "north", contract: contract, whisters: ["east"])
            ),
            "north"
        )
        XCTAssertEqual(
            DealSummaryPresentation.declarer(in: .misere(declarer: "east")),
            "east"
        )
        XCTAssertEqual(
            DealSummaryPresentation.declarer(
                in: .halfWhist(declarer: "south", contract: contract, halfWhister: "east")
            ),
            "south"
        )
        XCTAssertEqual(
            DealSummaryPresentation.declarer(
                in: .withoutThree(declarer: "north", bid: .game(contract))
            ),
            "north"
        )
    }

    func testNonContractResultsHaveNoDeclarer() {
        XCTAssertNil(DealSummaryPresentation.declarer(in: .passedOut))
        XCTAssertNil(DealSummaryPresentation.declarer(in: .allPass))
    }

    func testOpeningHandRowsAreSortedAndCappedAtFiveCards() {
        let cards = Array(Deck.standard32.reversed().prefix(10))
        let order = CardSuitDisplayOrder.spadesClubsDiamondsHearts
        let rows = DealSummaryPresentation.openingHandRows(cards, order: order)

        XCTAssertEqual(rows.map(\.count), [5, 5])
        XCTAssertEqual(
            rows.flatMap { $0 },
            cards.sortedForTableDisplay(order: order)
        )
    }
}
