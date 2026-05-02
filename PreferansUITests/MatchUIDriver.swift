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
        var engine = try PreferansEngine(
            players: script.players,
            rules: script.rules,
            match: script.match,
            firstDealer: script.firstDealer
        )
        for (index, deal) in script.deals.enumerated() {
            try driveDeal(deal, dealIndex: index, engine: &engine)
        }
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
        for player in script.players {
            XCTAssertEqual(robot.pool(of: player), summary.finalScore.pool[player] ?? 0,
                           "UI pool for \(player) drifted from internal engine.")
            XCTAssertEqual(robot.mountain(of: player), summary.finalScore.mountain[player] ?? 0,
                           "UI mountain for \(player) drifted from internal engine.")
        }
    }

    // MARK: - Per-deal driver

    private func driveDeal(_ deal: DealScript, dealIndex: Int, engine: inout PreferansEngine) throws {
        // The first deal opens from .waitingForDeal; subsequent deals open
        // from .dealFinished after the previous deal's last play.
        let entryPhase = dealIndex == 0 ? "Waiting for deal" : "Deal finished"
        robot.waitForPhase(entryPhase)
        robot.startNextDeal()

        // Build the deck the engine will consume — must match what the
        // script's TestHarness pre-built ScriptedDealSource hands to the UI.
        let dealer = engine.nextDealer
        let active = engine.activePlayers(forDealer: dealer)
        let deck = deal.recipe.deck(for: active)
        try engine.startDeal(deck: deck)

        robot.waitForPhase("Bidding")

        // Auction
        for call in deal.auction {
            guard case let .bidding(state) = engine.state else {
                XCTFail("Deal \(dealIndex): engine left bidding before all scripted calls were consumed; state = \(engine.state.description).")
                return
            }
            robot.bid(call)
            _ = try engine.apply(.bid(player: state.currentPlayer, call: call))
        }

        // Discard (declarer takes talon)
        if case let .awaitingDiscard(exchange) = engine.state {
            let cards: [Card]
            switch deal.discardChoice {
            case .talon:
                cards = exchange.talon
            case let .specific(specified):
                cards = specified
            case .none:
                XCTFail("Deal \(dealIndex): reached awaitingDiscard but discardChoice is .none.")
                return
            }
            robot.discard(cards)
            _ = try engine.apply(.discard(player: exchange.declarer, cards: cards))
        }

        // Contract declaration (game or totus strain pick)
        if case let .awaitingContract(declaration) = engine.state {
            guard let contract = deal.contractDeclaration else {
                XCTFail("Deal \(dealIndex): reached awaitingContract but contractDeclaration is nil.")
                return
            }
            robot.declareContract(contract)
            _ = try engine.apply(.declareContract(player: declaration.declarer, contract: contract))
        }

        // Whist responses (one per defender)
        for call in deal.whists {
            guard case let .awaitingWhist(state) = engine.state else { break }
            robot.whist(call)
            _ = try engine.apply(.whist(player: state.currentPlayer, call: call))
        }

        // Defender mode (when exactly one defender whists)
        if case let .awaitingDefenderMode(state) = engine.state {
            guard let mode = deal.defenderMode else {
                XCTFail("Deal \(dealIndex): reached awaitingDefenderMode but defenderMode is nil.")
                return
            }
            robot.defenderMode(mode)
            _ = try engine.apply(.chooseDefenderMode(player: state.whister, mode: mode))
        }

        // Card play
        try drivePlay(deal.cardPlay, dealIndex: dealIndex, engine: &engine)
    }

    private func drivePlay(_ strategy: CardPlayStrategy, dealIndex: Int, engine: inout PreferansEngine) throws {
        switch strategy {
        case .none:
            return
        case let .exact(cards):
            for card in cards {
                guard case let .playing(state) = engine.state else { return }
                robot.play(card, by: state.currentPlayer)
                _ = try engine.apply(.playCard(player: state.currentPlayer, card: card))
            }
        case let .greedyForDeclarer(declarer):
            try playLoop(engine: &engine, dealIndex: dealIndex) { actor, legal in
                actor == declarer
                    ? legal.max(by: { $0.rank.rawValue < $1.rank.rawValue })
                    : legal.min(by: { $0.rank.rawValue < $1.rank.rawValue })
            }
        case .lowestLegal:
            try playLoop(engine: &engine, dealIndex: dealIndex) { _, legal in
                legal.min(by: { $0.rank.rawValue < $1.rank.rawValue })
            }
        }
    }

    private func playLoop(
        engine: inout PreferansEngine,
        dealIndex: Int,
        choose: (PlayerID, [Card]) -> Card?
    ) throws {
        var safety = 64
        while case let .playing(state) = engine.state, safety > 0 {
            safety -= 1
            let actor = state.currentPlayer
            let legal = engine.legalCards(for: actor)
            guard let card = choose(actor, legal) else {
                XCTFail("Deal \(dealIndex): no legal card for \(actor) at trick \(state.completedTricks.count).")
                return
            }
            robot.play(card, by: actor)
            _ = try engine.apply(.playCard(player: actor, card: card))
        }
        if safety == 0 {
            XCTFail("Deal \(dealIndex): play loop did not terminate within 64 trick steps.")
        }
    }
}
