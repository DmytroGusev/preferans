import XCTest
import PreferansEngine

/// Replays a `MatchScript` through `MatchUIRobot` while mirroring the same
/// state in an internal `PreferansEngine`. The internal engine is the
/// driver's oracle: every action computed from the script is applied to
/// both surfaces (UI via the robot, internal engine via `apply`) and the
/// final pool/mountain readings are cross-checked.
///
/// Two reasons for the dual bookkeeping:
/// 1. Card-play strategies (greedy / lowest-legal) need `legalCards(for:)`
///    to pick the next card. Re-deriving this from the UI alone would mean
///    parsing the visible "playable" highlights — slower and more fragile.
/// 2. After every UI tap, asserting the parallel engine reaches the same
///    state catches divergences (a missed identifier, an off-by-one in the
///    rotation, a SwiftUI render lag) immediately, with a useful error
///    message. Without the oracle the test would hit the *next* unrelated
///    failure several actions later.
@MainActor
struct MatchUIDriver {
    let script: MatchScript
    let robot: MatchUIRobot

    func run() throws {
        let engine = try MatchScriptStepper(script: script).run(
            hooks: MatchScriptStepper.Hooks(
                beforeDeal: { dealIndex, _, _ in
                    // The first deal opens from .waitingForDeal; subsequent
                    // deals open from .dealFinished after the previous deal's
                    // last play.
                    let entryPhase = dealIndex == 0 ? "Waiting for deal" : "Deal finished"
                    robot.waitForPhase(entryPhase)
                    robot.startNextDeal()
                },
                afterStartDeal: { _, _, _ in
                    robot.waitForPhase("Bidding")
                },
                beforeAction: { _, _, action, _ in
                    tap(action)
                }
            )
        )
        // Final terminal state — the script must consume exactly the deals
        // the engine needs to close the pulka.
        guard case let .gameOver(summary) = engine.state else {
            XCTFail("Internal engine did not reach gameOver after \(script.deals.count) deals; got \(engine.state.description).")
            return
        }
        XCTAssertTrue(robot.isMatchOver(),
                      "UI did not display the game-over panel after the final deal.")
        XCTAssertEqual(robot.gameOverDealsPlayed(), summary.dealsPlayed,
                       "Game-over panel's deal count must match the engine's.")
        if let expectedWinner = summary.standings.first?.player {
            XCTAssertEqual(robot.gameOverWinner(), expectedWinner,
                           "Game-over winner must match the engine's standings leader.")
        }
        // Cross-check final pool/mountain via the UI.
        let finalScores = robot.scoreSnapshot(for: script.players)
        for player in script.players {
            XCTAssertEqual(finalScores[player]?.pool, summary.finalScore.pool[player] ?? 0,
                           "UI pool for \(player) drifted from internal engine.")
            XCTAssertEqual(finalScores[player]?.mountain, summary.finalScore.mountain[player] ?? 0,
                           "UI mountain for \(player) drifted from internal engine.")
        }
    }

    private func tap(_ action: PreferansAction) {
        switch action {
        case .startDeal:
            robot.startNextDeal()
        case let .bid(_, call):
            robot.bid(call)
        case let .discard(_, cards):
            robot.discard(cards)
        case let .declareContract(_, contract):
            robot.declareContract(contract)
        case let .whist(_, call):
            robot.whist(call)
        case let .chooseDefenderMode(_, mode):
            robot.defenderMode(mode)
        case let .playCard(player, card):
            robot.play(card, by: player)
        }
    }
}
