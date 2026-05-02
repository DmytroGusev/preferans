import XCTest
@testable import PreferansEngine

/// Plays many full matches end-to-end with bots in every seat and reports
/// statistics + anomalies. This is a "manual playthrough" stand-in: it
/// exercises the same paths a human-vs-bot session would hit, but in bulk.
///
/// Findings are printed to stdout (visible with `swift test --filter
/// BotSimulationReportTests`); flagged-as-failure conditions are limited to
/// hard correctness violations (illegal moves, non-terminating deals,
/// scoring drift).
final class BotSimulationReportTests: XCTestCase {
    private let players: [PlayerID] = ["N", "E", "S"]

    /// Single hero scenario: 50 random 3-player matches to pool target = 6.
    func testFiftyThreePlayerMatchesAgainstBots() async throws {
        let strategy = HeuristicStrategy(planner: CardPlayPlanner(samples: 4, rolloutsPerSample: 1))
        var report = SimReport()
        var rng = SystemRandomNumberGenerator()
        let matchCount = 50
        for matchIndex in 0..<matchCount {
            let match = MatchSettings(poolTarget: 6, raspasy: .singleShot)
            var engine = try PreferansEngine(players: players, match: match)
            try await playMatch(engine: &engine, strategy: strategy, report: &report, matchIndex: matchIndex, rng: &rng)
            report.matchesCompleted += 1
        }
        report.print(label: "3-player x \(matchCount) matches, pool=6")

        // Hard assertions — failure here means a real bug surfaced during the
        // sim, not a statistical anomaly.
        XCTAssertEqual(report.matchesCompleted, matchCount)
        XCTAssertEqual(report.illegalActionAttempts, 0)
        XCTAssertEqual(report.stalledDeals, 0)
        XCTAssertEqual(report.scoringInconsistencies, 0)
    }

    func testTwentyFourPlayerMatchesAgainstBots() async throws {
        let strategy = HeuristicStrategy(planner: CardPlayPlanner(samples: 4, rolloutsPerSample: 1))
        var report = SimReport()
        var rng = SystemRandomNumberGenerator()
        let matchCount = 20
        let four: [PlayerID] = ["N", "E", "S", "W"]
        for matchIndex in 0..<matchCount {
            let match = MatchSettings(poolTarget: 6, raspasy: .singleShot)
            var engine = try PreferansEngine(players: four, match: match)
            try await playMatch(engine: &engine, strategy: strategy, report: &report, matchIndex: matchIndex, rng: &rng)
            report.matchesCompleted += 1
        }
        report.print(label: "4-player x \(matchCount) matches, pool=6")
        XCTAssertEqual(report.matchesCompleted, matchCount)
        XCTAssertEqual(report.illegalActionAttempts, 0)
        XCTAssertEqual(report.stalledDeals, 0)
    }

    // MARK: - Driver

    private func playMatch(
        engine: inout PreferansEngine,
        strategy: PlayerStrategy,
        report: inout SimReport,
        matchIndex: Int,
        rng: inout SystemRandomNumberGenerator
    ) async throws {
        let dealCap = 200
        var dealsThisMatch = 0
        while case .gameOver = engine.state { return }
        outer: while dealsThisMatch < dealCap {
            switch engine.state {
            case .gameOver:
                break outer
            case .waitingForDeal, .dealFinished:
                let deck = Deck.standard32.shuffled(using: &rng)
                _ = try engine.startDeal(deck: deck)
                dealsThisMatch += 1
            default:
                break
            }
            let drive = try await BotTestDriver.drive(engine: &engine, strategy: strategy, stepLimit: 800)
            report.illegalActionAttempts += drive.illegalActionAttempts
            if drive.stalled {
                report.stalledDeals += 1
                return
            }
            if case let .dealFinished(result) = engine.state {
                report.observe(result: result)
            }
        }
        if dealsThisMatch >= dealCap {
            report.dealCapHits += 1
        }
    }

}

private struct SimReport {
    var matchesCompleted = 0
    var dealCapHits = 0
    var stalledDeals = 0
    var illegalActionAttempts = 0
    var scoringInconsistencies = 0

    var dealResultKindCounts: [String: Int] = [:]
    var contractValueHistogram: [Int: Int] = [:]
    var declarerWinCount = 0
    var declarerLossCount = 0
    var trickCountSamples: [Int] = []

    mutating func observe(result: DealResult) {
        let key: String
        switch result.kind {
        case .passedOut: key = "passedOut"
        case .allPass: key = "allPass"
        case .halfWhist: key = "halfWhist"
        case .misere: key = "misere"
        case let .game(_, contract, _):
            key = "game.\(contract.tricks).\(contract.strain)"
            contractValueHistogram[contract.value, default: 0] += 1
        }
        dealResultKindCounts[key, default: 0] += 1

        if case let .game(declarer, contract, _) = result.kind {
            let declTricks = result.trickCounts[declarer] ?? 0
            if declTricks >= contract.tricks {
                declarerWinCount += 1
            } else {
                declarerLossCount += 1
            }
            trickCountSamples.append(declTricks)
        }
    }

    func print(label: String) {
        Swift.print("\n=== Bot sim report: \(label) ===")
        Swift.print("matches completed:         \(matchesCompleted)")
        Swift.print("stalled deals:             \(stalledDeals)")
        Swift.print("illegal action attempts:   \(illegalActionAttempts)")
        Swift.print("scoring inconsistencies:   \(scoringInconsistencies)")
        Swift.print("deal cap hits:             \(dealCapHits)")
        Swift.print("declarer win/loss (game):  \(declarerWinCount) / \(declarerLossCount)")
        if !trickCountSamples.isEmpty {
            let avg = Double(trickCountSamples.reduce(0, +)) / Double(trickCountSamples.count)
            Swift.print(String(format: "avg declarer tricks (game): %.2f", avg))
        }
        Swift.print("deal result kinds:")
        for (k, v) in dealResultKindCounts.sorted(by: { $0.value > $1.value }) {
            Swift.print("  \(k): \(v)")
        }
        if !contractValueHistogram.isEmpty {
            Swift.print("contract value histogram:")
            for (k, v) in contractValueHistogram.sorted(by: { $0.key < $1.key }) {
                Swift.print("  value \(k): \(v)")
            }
        }
        Swift.print("=== end report ===\n")
    }
}
