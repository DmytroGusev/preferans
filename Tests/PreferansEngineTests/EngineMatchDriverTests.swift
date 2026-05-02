import XCTest
@testable import PreferansEngine

/// End-to-end engine-level tests for the three canonical match scripts.
/// Each test runs the script through `EngineMatchDriver`, asserts it ends in
/// `.gameOver` after exactly the listed deals, and validates the contract
/// mix matches the design's "every contract type at least once + multiple
/// failures" requirement.
///
/// These tests must pass before the UI-level driver is wired up — they are
/// the cheapest way to catch a broken script (10ms vs ~60s in the simulator).
final class EngineMatchDriverTests: XCTestCase {
    // MARK: - Per-script smoke tests

    func testGame1ClassicSochiReachesGameOverOnExpectedDeal() throws {
        let script = MatchScriptFixtures.game1ClassicSochi
        let summary = try EngineMatchDriver(script: script).run()

        XCTAssertEqual(summary.dealsPlayed, script.deals.count,
                       "Game 1 must consume exactly the scripted deals before gameOver fires.")
        XCTAssertGreaterThanOrEqual(
            summary.finalScore.pool.values.reduce(0, +),
            script.match.poolTarget,
            "Pool sum must reach or exceed the target on the final deal."
        )
    }

    func testGame2LongSochiReachesGameOverOnExpectedDeal() throws {
        let script = MatchScriptFixtures.game2LongSochi
        let summary = try EngineMatchDriver(script: script).run()

        XCTAssertEqual(summary.dealsPlayed, script.deals.count)
        XCTAssertGreaterThanOrEqual(
            summary.finalScore.pool.values.reduce(0, +),
            script.match.poolTarget
        )
    }

    func testGame3RostovDedicatedTotusReachesGameOverOnExpectedDeal() throws {
        let script = MatchScriptFixtures.game3RostovDedicatedTotus
        let summary = try EngineMatchDriver(script: script).run()

        XCTAssertEqual(summary.dealsPlayed, script.deals.count)
        XCTAssertGreaterThanOrEqual(
            summary.finalScore.pool.values.reduce(0, +),
            script.match.poolTarget
        )
    }

    // MARK: - Pool-sum trajectory

    func testEachScriptCrossesPoolTargetOnTheFinalDealNotEarlier() throws {
        for script in [
            MatchScriptFixtures.game1ClassicSochi,
            MatchScriptFixtures.game2LongSochi,
            MatchScriptFixtures.game3RostovDedicatedTotus
        ] {
            try assertPoolGateFiresOnFinalDeal(script: script)
        }
    }

    /// Runs each prefix of the script (1, 2, ..., n-1 deals) and confirms the
    /// engine does NOT enter gameOver. Then runs the full script and confirms
    /// it DOES. Catches off-by-one errors in fixture trajectories.
    private func assertPoolGateFiresOnFinalDeal(script: MatchScript) throws {
        for prefixCount in 1..<script.deals.count {
            let prefix = MatchScript(
                players: script.players,
                firstDealer: script.firstDealer,
                rules: script.rules,
                match: script.match,
                deals: Array(script.deals.prefix(prefixCount))
            )
            do {
                _ = try EngineMatchDriver(script: prefix).run()
                XCTFail("Script with \(prefixCount)/\(script.deals.count) deals should not reach gameOver yet.")
            } catch let MatchScriptError.matchDidNotReachGameOver(state) {
                XCTAssertEqual(state, "dealFinished", "After \(prefixCount) deals expected dealFinished; got \(state).")
            } catch {
                XCTFail("Unexpected error running prefix of length \(prefixCount): \(error)")
            }
        }
        // Full script: must reach gameOver.
        let summary = try EngineMatchDriver(script: script).run()
        XCTAssertEqual(summary.dealsPlayed, script.deals.count)
    }

    // MARK: - Contract-mix coverage

    func testEachScriptIncludesEveryRequiredContractType() throws {
        for script in [
            MatchScriptFixtures.game1ClassicSochi,
            MatchScriptFixtures.game2LongSochi,
            MatchScriptFixtures.game3RostovDedicatedTotus
        ] {
            let engine = try EngineMatchDriver(script: script).runReturningEngine()
            guard case let .gameOver(summary) = engine.state else {
                return XCTFail("Script did not reach gameOver: \(engine.state.description)")
            }
            // Walk the score sheet and check at least one of each: pool credit
            // (made contract), mountain charge (failed contract), whist credit
            // (defender on a real deal). The fixture fingerprint is documented
            // inline in MatchScriptFixtures.swift; here we just assert the
            // shape so a careless edit doesn't leave a fixture without
            // coverage.
            let totalPool = summary.finalScore.pool.values.reduce(0, +)
            let totalMountain = summary.finalScore.mountain.values.reduce(0, +)
            let totalWhists = summary.finalScore.whists.values
                .flatMap { $0.values }
                .reduce(0, +)
            XCTAssertGreaterThan(totalPool, 0, "Script must include at least one pool-crediting deal.")
            XCTAssertGreaterThan(totalMountain, 0, "Script must include at least one failed contract.")
            XCTAssertGreaterThan(totalWhists, 0, "Script must include at least one whist-crediting defender turn.")
        }
    }

    func testSuiteIncludesAtLeastFourFailedContractsAcrossThreeGames() {
        let allScripts = [
            MatchScriptFixtures.game1ClassicSochi,
            MatchScriptFixtures.game2LongSochi,
            MatchScriptFixtures.game3RostovDedicatedTotus
        ]
        let totalFailedAcrossSuite = allScripts.reduce(0) { running, script in
            running + script.deals.filter { deal in
                if case .declarerFails = deal.recipe { return true }
                if case .totusFails = deal.recipe { return true }
                return false
            }.count
        }
        XCTAssertGreaterThanOrEqual(totalFailedAcrossSuite, 4,
                                     "The 3-script suite must exercise at least four failed contracts in total.")
    }

    // MARK: - Chained dealer rotation across games

    func testDealerRotationContinuesAcrossGameBoundaries() throws {
        // Run game 1, observe nextDealer at gameOver, expect game 2's
        // firstDealer matches (real-world rotation continues at the same
        // table). Same for game 2 → game 3.
        let game1Engine = try EngineMatchDriver(script: MatchScriptFixtures.game1ClassicSochi)
            .runReturningEngine()
        XCTAssertEqual(game1Engine.nextDealer, MatchScriptFixtures.game2LongSochi.firstDealer,
                       "Game 2's firstDealer must continue the rotation from where game 1 left off.")

        let game2Engine = try EngineMatchDriver(script: MatchScriptFixtures.game2LongSochi)
            .runReturningEngine()
        XCTAssertEqual(game2Engine.nextDealer, MatchScriptFixtures.game3RostovDedicatedTotus.firstDealer,
                       "Game 3's firstDealer must continue the rotation from where game 2 left off.")
    }

    /// Drives a script through the real `EngineMatchDriver` and returns the
    /// per-deal pool/mountain history. Used to diagnose trajectory drift
    /// when fixture deals are tuned.
    private func trajectory(of script: MatchScript) throws -> [(pool: [PlayerID: Int], mountain: [PlayerID: Int])] {
        var snapshots: [(pool: [PlayerID: Int], mountain: [PlayerID: Int])] = []
        for prefixCount in 1...script.deals.count {
            let openMatch = MatchSettings(
                poolTarget: .max,
                raspasy: script.match.raspasy,
                totus: script.match.totus
            )
            let prefix = MatchScript(
                players: script.players,
                firstDealer: script.firstDealer,
                rules: script.rules,
                match: openMatch,
                deals: Array(script.deals.prefix(prefixCount))
            )
            // Driver normally requires gameOver; with poolTarget=.max it
            // ends in dealFinished — use runReturningEngine and inspect.
            do {
                let engine = try EngineMatchDriver(script: prefix).runReturningEngine()
                snapshots.append((engine.score.pool, engine.score.mountain))
            } catch let MatchScriptError.matchDidNotReachGameOver(state) where state == "dealFinished" {
                // Expected — pool target is .max so we never hit gameOver.
                XCTFail("openMatch driver should not throw matchDidNotReachGameOver — it should just return the engine.")
            }
        }
        return snapshots
    }


    // MARK: - Engine state at end of match

    func testGameOverIsTerminalForFullMatch() throws {
        let engine = try EngineMatchDriver(script: MatchScriptFixtures.game1ClassicSochi)
            .runReturningEngine()
        guard case .gameOver = engine.state else {
            return XCTFail("Expected gameOver; got \(engine.state.description)")
        }
        // startDeal from gameOver must throw — already covered in
        // MatchSettingsTests, asserted again at the script level for safety.
        var mutable = engine
        XCTAssertThrowsError(try mutable.startDeal(deck: Deck.standard32))
    }
}
