import XCTest
@testable import PreferansEngine
@testable import PreferansEngineTestSupport

/// Plays many full matches end-to-end with bots in every seat and reports
/// statistics and anomalies. This checks engine completion and legality;
/// simulator interaction, pacing, and human judgments need separate evidence.
///
/// Findings are printed to stdout (visible with `swift test --filter
/// BotSimulationReportTests`); flagged-as-failure conditions are limited to
/// hard correctness violations (illegal moves, non-terminating deals,
/// scoring drift).
final class BotSimulationReportTests: XCTestCase {
    private let players: [PlayerID] = ["N", "E", "S"]

    /// Every `swift test` plays a small smoke batch so
    /// the path can't rot; export `PREF_SIM_FULL=1` for the full statistical
    /// run (nightly / pre-release / after strategy changes).
    private var fullSim: Bool {
        ProcessInfo.processInfo.environment["PREF_SIM_FULL"] == "1"
    }

    /// Single hero scenario: seeded 3-player matches to pool target = 6.
    func testFiftyThreePlayerMatchesAgainstBots() async throws {
        let strategy = HeuristicStrategy(planner: CardPlayPlanner(samples: 4))
        var report = SimReport()
        var rng = SeededRandomNumberGenerator(seed: 0x3342_4F54_5349_4D)
        let matchCount = fullSim ? 50 : 5
        for matchIndex in 0..<matchCount {
            let match = MatchSettings(poolTarget: 6, raspasy: .singleShot)
            var engine = try PreferansEngine(players: players, match: match)
            if try await playMatch(engine: &engine, strategy: strategy, report: &report, matchIndex: matchIndex, rng: &rng) {
                report.matchesCompleted += 1
            }
        }
        report.print(label: "3-player x \(matchCount) matches, table pool=6")

        // Hard assertions — failure here means a real bug surfaced during the
        // sim, not a statistical anomaly.
        XCTAssertEqual(report.matchesCompleted, matchCount)
        XCTAssertEqual(report.illegalActionAttempts, 0)
        XCTAssertEqual(report.stalledDeals, 0)
        XCTAssertEqual(report.scoringInconsistencies, 0)
        XCTAssertEqual(report.dealCapHits, 0)
        XCTAssertEqual(report.timeLimitHits, 0)
    }

    func testTwentyFourPlayerMatchesAgainstBots() async throws {
        let strategy = HeuristicStrategy(planner: CardPlayPlanner(samples: 4))
        var report = SimReport()
        var rng = SeededRandomNumberGenerator(seed: 0x3442_4F54_5349_4D)
        let matchCount = fullSim ? 20 : 3
        let four: [PlayerID] = ["N", "E", "S", "W"]
        for matchIndex in 0..<matchCount {
            let match = MatchSettings(poolTarget: 6 * four.count, raspasy: .singleShot)
            var engine = try PreferansEngine(players: four, match: match)
            if try await playMatch(engine: &engine, strategy: strategy, report: &report, matchIndex: matchIndex, rng: &rng) {
                report.matchesCompleted += 1
            }
        }
        report.print(label: "4-player x \(matchCount) matches, pool=6 per player")
        XCTAssertEqual(report.matchesCompleted, matchCount)
        XCTAssertEqual(report.illegalActionAttempts, 0)
        XCTAssertEqual(report.stalledDeals, 0)
        XCTAssertEqual(report.scoringInconsistencies, 0)
        XCTAssertEqual(report.dealCapHits, 0)
        XCTAssertEqual(report.timeLimitHits, 0)
    }

    // MARK: - Driver

    private func playMatch(
        engine: inout PreferansEngine,
        strategy: PlayerStrategy,
        report: inout SimReport,
        matchIndex: Int,
        rng: inout SeededRandomNumberGenerator
    ) async throws -> Bool {
        let started = Date()
        for deal in 1...200 {
            guard Date().timeIntervalSince(started) < 30 else {
                report.timeLimitHits += 1
                return false
            }
            switch engine.state {
            case .gameOver:
                return true
            case .waitingForDeal, .dealFinished:
                let deck = Deck.standard32.shuffled(using: &rng)
                _ = try engine.startDeal(deck: deck)
            default:
                break
            }
            let drive = try await BotTestDriver.drive(engine: &engine, strategy: strategy, stepLimit: 800)
            report.illegalActionAttempts += drive.illegalActionAttempts
            if drive.stalled {
                report.stalledDeals += 1
                return false
            }
            switch engine.state {
            case let .dealFinished(result):
                report.observe(result: result, players: engine.players)
                print("[bot-match] seats=\(engine.players.count) match=\(matchIndex + 1) deal=\(deal) phase=scored")
            case let .gameOver(summary):
                // The closing deal never enters dealFinished. Include it in
                // the report and require a real, coherent terminal state.
                report.observe(result: summary.lastDeal, players: engine.players)
                if !engine.match.isPoolClosed(summary.finalScore)
                    || abs(summary.standings.map(\.balance).reduce(0, +)) > 1e-8 {
                    report.scoringInconsistencies += 1
                }
                let elapsed = Date().timeIntervalSince(started)
                report.longestMatchSeconds = max(report.longestMatchSeconds, elapsed)
                if elapsed >= 30 { report.timeLimitHits += 1 }
                print("[bot-match] seats=\(engine.players.count) match=\(matchIndex + 1) deal=\(deal) phase=finished seconds=\(String(format: "%.2f", elapsed))")
                return true
            default:
                report.stalledDeals += 1
                return false
            }
        }
        report.dealCapHits += 1
        return false
    }

}

private struct SimReport {
    var matchesCompleted = 0
    var dealCapHits = 0
    var timeLimitHits = 0
    var longestMatchSeconds = 0.0
    var stalledDeals = 0
    var illegalActionAttempts = 0
    var scoringInconsistencies = 0

    var dealResultKindCounts: [String: Int] = [:]
    var contractValueHistogram: [Int: Int] = [:]
    var declarerWinCount = 0
    var declarerLossCount = 0
    var trickCountSamples: [Int] = []

    mutating func observe(result: DealResult, players: [PlayerID]) {
        if (try? result.scoreDelta.validate(players: players)) == nil {
            scoringInconsistencies += 1
        }

        let key: String
        switch result.kind {
        case .passedOut: key = "passedOut"
        case .withoutThree: key = "withoutThree"
        case .allPass: key = "allPass"
        case .halfWhist: key = "halfWhist"
        case .misere: key = "misere"
        case let .game(_, contract, _):
            key = "game.\(contract.tricks).\(contract.strain)"
            contractValueHistogram[contract.value, default: 0] += 1
        }
        dealResultKindCounts[key, default: 0] += 1

        switch result.kind {
        case .game, .misere, .allPass:
            if result.trickCounts.values.reduce(0, +) != 10 {
                scoringInconsistencies += 1
            }
        case .passedOut, .withoutThree, .halfWhist:
            if result.trickCounts.values.contains(where: { $0 != 0 }) {
                scoringInconsistencies += 1
            }
        }

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
        Swift.print("time limit hits:           \(timeLimitHits)")
        Swift.print(String(format: "longest match (seconds):   %.2f", longestMatchSeconds))
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
