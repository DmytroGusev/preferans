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
            players: ["north", "east", "south"],
            rules: .sochi
        )

        XCTAssertEqual(rows.map(\.pool), [2, 0, 0])
        XCTAssertEqual(rows.map(\.mountain), [0, 1, 0])
        XCTAssertEqual(rows.map(\.whistsIn), [4, 6, 0], "The writer earns the whists")
        XCTAssertEqual(rows.map(\.whistsOut), [6, 0, 4], "The target owes the whists")
        // Raw values: [20 + 4 - 6, -10 + 6, -4] = [18, -4, -4].
        // Subtract the mean 10/3 from every seat, including the idle one.
        assertBalances(rows, [44.0 / 3, -22.0 / 3, -22.0 / 3])
    }

    func testScoreDeltaBalanceUsesActiveConventionConversionValues() {
        let players: [PlayerID] = ["north", "east", "south"]
        var delta = ScoreDelta(players: players)
        delta.addPool(1, to: "north")
        delta.addMountain(1, to: "north")
        delta.addWhists(4, writer: "north", on: "east")
        delta.addWhists(2, writer: "east", on: "north")

        assertBalances(
            DealScoreDeltaPresentation.rows(from: delta, players: players, rules: .sochi),
            [2, -2, 0]
        )
        // Leningrad pool points convert at 20: raw [12, -2, 0], mean 10/3.
        assertBalances(
            DealScoreDeltaPresentation.rows(from: delta, players: players, rules: .leningrad),
            [26.0 / 3, -16.0 / 3, -10.0 / 3]
        )
    }

    func testMadeSixWithUnderwhistMatchesWorkedSimulatorDeal() {
        let players: [PlayerID] = ["Neo", "Morpheus", "Trinity"]
        var delta = ScoreDelta(players: players)
        delta.addPool(2, to: "Trinity")
        delta.addMountain(2, to: "Morpheus")
        delta.addWhists(6, writer: "Morpheus", on: "Trinity")

        let rows = DealScoreDeltaPresentation.rows(from: delta, players: players, rules: .sochi)
        // Trinity earns 20 and owes 6; Morpheus owes 20 and earns 6.
        assertBalances(rows, [0, -14, 14])
        XCTAssertEqual(rows[1].whistsIn, 6)
        XCTAssertEqual(rows[2].whistsOut, 6)
    }

    func testPoolCreditChangesEverySeatIncludingSittingOutDealer() {
        let players: [PlayerID] = ["north", "east", "south", "west"]
        var delta = ScoreDelta(players: players)
        delta.addPool(2, to: "east")

        assertBalances(
            DealScoreDeltaPresentation.rows(from: delta, players: players, rules: .sochi),
            [-5, 15, -5, -5]
        )
    }

    func testPostClosureDeltaIsNotClosedAgainAndMatchesRunningScoreChange() {
        let players: [PlayerID] = ["north", "east", "south"]
        var score = ScoreSheet(players: players)
        var opening = ScoreDelta(players: players)
        opening.addPool(2, to: "north")
        opening.addPool(1, to: "east")
        score.apply(opening, closingAtPoolTarget: 6)
        let before = score.normalizedBalances()

        var earned = ScoreDelta(players: players)
        earned.addPool(3, to: "north")
        let applied = score.apply(earned, closingAtPoolTarget: 6)
        let rows = DealScoreDeltaPresentation.rows(from: applied, players: players, rules: .sochi)
        let after = score.normalizedBalances()

        XCTAssertEqual(rows.map(\.pool), [0, 1, 2])
        for row in rows {
            XCTAssertEqual(row.balance, after[row.player]! - before[row.player]!, accuracy: 0.0001)
        }
        XCTAssertEqual(rows.map(\.balance).reduce(0, +), 0, accuracy: 0.0001)
    }

    func testFractionalBalancesKeepPrecisionAndSuppressNegativeZero() {
        XCTAssertEqual(ScoreFormatting.balance(40.0 / 3), "+13.3")
        XCTAssertEqual(ScoreFormatting.balance(-20.0 / 3), "-6.7")
        XCTAssertEqual(ScoreFormatting.balance(-0.00001), "0.0")
    }

    private func assertBalances(
        _ rows: [DealScoreDeltaRow], _ expected: [Double],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(rows.count, expected.count, file: file, line: line)
        for (row, balance) in zip(rows, expected) {
            XCTAssertEqual(row.balance, balance, accuracy: 0.0001, file: file, line: line)
        }
        XCTAssertEqual(rows.map(\.balance).reduce(0, +), 0, accuracy: 0.0001, file: file, line: line)
    }
}
