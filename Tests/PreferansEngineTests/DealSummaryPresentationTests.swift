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

    func testScoreDeltaRowsSeparatePoolMountainAndDirectedWhists() {
        var delta = ScoreDelta(players: ["north", "east", "south"])
        delta.addPool(2, to: "north")
        delta.addMountain(1, to: "east")
        delta.addWhists(6, writer: "east", on: "north")
        delta.addWhists(4, writer: "north", on: "south")

        let rows = DealScoreDeltaPresentation.rows(
            from: delta,
            players: ["north", "east", "south"]
        )

        XCTAssertEqual(rows[0], DealScoreDeltaRow(
            player: "north", pool: 2, mountain: 0, whistsIn: 6, whistsOut: 4
        ))
        XCTAssertEqual(rows[1], DealScoreDeltaRow(
            player: "east", pool: 0, mountain: 1, whistsIn: 0, whistsOut: 6
        ))
        XCTAssertEqual(rows[2], DealScoreDeltaRow(
            player: "south", pool: 0, mountain: 0, whistsIn: 4, whistsOut: 0
        ))
    }

    func testScoreDeltaBalanceUsesActiveConventionConversionValues() {
        let row = DealScoreDeltaRow(
            player: "north", pool: 1, mountain: 1, whistsIn: 4, whistsOut: 2
        )

        XCTAssertEqual(
            DealScoreDeltaPresentation.balanceDelta(for: row, rules: .sochi),
            2
        )
        XCTAssertEqual(
            DealScoreDeltaPresentation.balanceDelta(for: row, rules: .leningrad),
            12
        )
    }
}
