import XCTest
@testable import PreferansEngine
@testable import PreferansEngineTestSupport

final class ScoringCalculationTests: XCTestCase {
    private let players: [PlayerID] = ["north", "east", "south"]

    func testMadeContractCreditsPoolAndEachWhistersOwnTricks() {
        let delta = scoreGame(
            contract: GameContract(6, .suit(.clubs)),
            whisters: ["east", "south"],
            trickCounts: ["north": 6, "east": 2, "south": 2]
        )

        XCTAssertEqual(delta.pool["north"], 2)
        XCTAssertEqual(delta.mountain["east"], 0)
        XCTAssertEqual(delta.mountain["south"], 0)
        XCTAssertEqual(delta.whists["east"]?["north"], 4)
        XCTAssertEqual(delta.whists["south"]?["north"], 4)
    }

    func testFailedDeclarerPaysMountainAndEachDefenderConsolationWhists() {
        let delta = scoreGame(
            contract: GameContract(7, .suit(.hearts)),
            whisters: ["east", "south"],
            trickCounts: ["north": 5, "east": 3, "south": 2]
        )

        XCTAssertEqual(delta.pool["north"], 0)
        XCTAssertEqual(delta.mountain["north"], 8)
        XCTAssertEqual(delta.whists["east"]?["north"], 20)
        XCTAssertEqual(delta.whists["south"]?["north"], 16)
    }

    func testSingleGreedyWhisterScoresAllDefenderTricksAndOwnResponsibility() {
        let delta = scoreGame(
            contract: GameContract(6, .suit(.diamonds)),
            whisters: ["east"],
            trickCounts: ["north": 7, "east": 1, "south": 2]
        )

        XCTAssertEqual(delta.pool["north"], 2)
        XCTAssertEqual(delta.whists["east"]?["north"], 6)
        XCTAssertEqual(delta.mountain["east"], 2)
        XCTAssertEqual(delta.whists["south"]?["north"], nil)
    }

    func testOwnHandOnlySingleWhisterDoesNotScorePassedDefenderTricks() {
        let rules = PreferansRules(singleWhistScoring: .ownHandOnly)
        let delta = scoreGame(
            contract: GameContract(6, .suit(.diamonds)),
            whisters: ["east"],
            trickCounts: ["north": 7, "east": 1, "south": 2],
            rules: rules
        )

        XCTAssertEqual(delta.pool["north"], 2)
        XCTAssertEqual(delta.whists["east"]?["north"], 2)
        XCTAssertEqual(delta.mountain["east"], 2)
    }

    func testOddOneTrickResponsibilityFallsOnSecondWhister() {
        let delta = scoreGame(
            contract: GameContract(8, .suit(.spades)),
            whisters: ["east", "south"],
            trickCounts: ["north": 10, "east": 0, "south": 0]
        )

        XCTAssertEqual(delta.pool["north"], 6)
        XCTAssertEqual(delta.mountain["east"], 0)
        XCTAssertEqual(delta.mountain["south"], 6)
        XCTAssertEqual(delta.whists["east"]?["north"], nil)
        XCTAssertEqual(delta.whists["south"]?["north"], nil)
    }

    private func scoreGame(
        contract: GameContract,
        whisters: [PlayerID],
        trickCounts: [PlayerID: Int],
        rules: PreferansRules = .sochi,
        match: MatchSettings = .unbounded
    ) -> ScoreDelta {
        let scoring = PreferansScoring(players: players, rules: rules, match: match)
        let defenders = players.filter { $0 != "north" }
        let context = GamePlayContext(
            declarer: "north",
            contract: contract,
            defenders: defenders,
            whisters: whisters,
            defenderPlayMode: whisters.count == 1 ? .open : .closed,
            whistCalls: defenders.map { defender in
                WhistCallRecord(player: defender, call: whisters.contains(defender) ? .whist : .pass)
            }
        )
        let playing = PlayingState(
            dealer: "south",
            activePlayers: players,
            hands: Dictionary(uniqueKeysWithValues: players.map { ($0, [Card]()) }),
            talon: [],
            leader: "north",
            currentPlayer: "north",
            trickCounts: trickCounts,
            kind: .game(context)
        )
        return scoring.completedPlay(playing).scoreDelta
    }
}
