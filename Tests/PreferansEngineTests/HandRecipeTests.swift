import XCTest
@testable import PreferansEngine

/// Each test drives the engine end-to-end against a recipe-built deck and
/// asserts the recipe's named outcome is what actually happens. The deck is
/// also validated for shape (32 unique standard cards in the engine's packet
/// order) so a malformed deck fails loudly here rather than silently in a
/// downstream MatchScript test.
final class HandRecipeTests: XCTestCase {
    private let activePlayers: [PlayerID] = ["north", "east", "south"]

    /// Mirrors ``PreferansEngine``'s `activePlayers(forDealer:)` so a recipe
    /// caller can construct the deck against the *same* rotation the engine
    /// will use when it deals. Without this, the recipe interleaves cards in
    /// a different seat order than the engine assigns them and every hand
    /// lands in the wrong seat.
    private func activeRotation(players: [PlayerID], firstDealer: PlayerID) -> [PlayerID] {
        let dealerIndex = players.firstIndex(of: firstDealer)!
        let count = players.count
        var rotation: [PlayerID] = []
        var offset = 1
        while rotation.count < 3 {
            let candidate = players[(dealerIndex + offset) % count]
            if count == 3 || candidate != firstDealer {
                rotation.append(candidate)
            }
            offset += 1
        }
        return rotation
    }

    // MARK: - Deck shape

    func testEveryRecipeBuildsAValid32CardDeck() throws {
        let recipes: [HandRecipe] = [
            .declarerWins(declarer: "north", contract: GameContract(6, .suit(.spades))),
            .declarerWins(declarer: "east", contract: GameContract(9, .suit(.clubs))),
            .declarerFails(declarer: "south", contract: GameContract(8, .suit(.hearts)), declarerWillTake: 5),
            .cleanMisere(declarer: "north"),
            .totusMakes(declarer: "east", strain: .suit(.diamonds)),
            .totusFails(declarer: "south", strain: .suit(.spades), declarerWillTake: 7),
            .raspasyCleanExit(cleaner: "north", talonLeadSuit: nil),
            .raspasyCleanExit(cleaner: "east", talonLeadSuit: .clubs)
        ]
        for recipe in recipes {
            let deck = recipe.deck(for: activePlayers)
            XCTAssertEqual(deck.count, 32, "Recipe \(recipe) produced wrong card count.")
            XCTAssertEqual(Set(deck), Set(Deck.standard32), "Recipe \(recipe) is not a permutation of the standard deck.")
        }
    }

    // MARK: - declarerWins

    func testDeclarerWinsRecipeMakesContractWithGreedyPlay() throws {
        let recipe = HandRecipe.declarerWins(declarer: "north", contract: GameContract(6, .suit(.spades)))
        var engine = try PreferansEngine(players: activePlayers, firstDealer: "south")
        try engine.startDeal(deck: recipe.deck(for: activePlayers))

        try driveAuctionWinning(engine: &engine, declarer: "north", bid: .game(GameContract(6, .suit(.spades))))
        try discardTalon(engine: &engine, declarer: "north")
        try declareContract(engine: &engine, declarer: "north", contract: GameContract(6, .suit(.spades)))
        try forceWhist(engine: &engine, defenders: ["east", "south"])
        try playOut(engine: &engine, declarer: "north")

        guard case let .dealFinished(result) = engine.state, case .game = result.kind else {
            return XCTFail("Expected dealFinished.game; got \(engine.state.description).")
        }
        XCTAssertGreaterThanOrEqual(result.trickCounts["north"] ?? 0, 6,
                                    "declarerWins must take at least the contract trick count.")
        XCTAssertGreaterThan(engine.score.pool["north"] ?? 0, 0,
                             "Declarer must be credited pool when contract is made.")
    }

    func testHighContractDeclarerWinsAtNineTricks() throws {
        let recipe = HandRecipe.declarerWins(declarer: "east", contract: GameContract(9, .suit(.clubs)))
        let players: [PlayerID] = ["north", "east", "south"]
        let firstDealer: PlayerID = "north"
        let rotation = activeRotation(players: players, firstDealer: firstDealer)
        XCTAssertEqual(rotation, ["east", "south", "north"],
                       "Sanity: rotation helper must match engine's activePlayers(forDealer:).")

        var engine = try PreferansEngine(players: players, firstDealer: firstDealer)
        try engine.startDeal(deck: recipe.deck(for: rotation))

        try driveAuctionWinning(engine: &engine, declarer: "east", bid: .game(GameContract(9, .suit(.clubs))))
        try discardTalon(engine: &engine, declarer: "east")
        try declareContract(engine: &engine, declarer: "east", contract: GameContract(9, .suit(.clubs)))
        try forceWhist(engine: &engine, defenders: ["south", "north"])
        try playOut(engine: &engine, declarer: "east")

        guard case let .dealFinished(result) = engine.state, case .game = result.kind else {
            return XCTFail("Expected dealFinished.game; got \(engine.state.description).")
        }
        XCTAssertGreaterThanOrEqual(result.trickCounts["east"] ?? 0, 9)
    }

    // MARK: - declarerFails

    func testDeclarerFailsRecipeProducesExactUndertricks() throws {
        let recipe = HandRecipe.declarerFails(
            declarer: "north",
            contract: GameContract(8, .suit(.spades)),
            declarerWillTake: 6
        )
        var engine = try PreferansEngine(players: activePlayers, firstDealer: "south")
        try engine.startDeal(deck: recipe.deck(for: activePlayers))

        try driveAuctionWinning(engine: &engine, declarer: "north", bid: .game(GameContract(8, .suit(.spades))))
        try discardTalon(engine: &engine, declarer: "north")
        try declareContract(engine: &engine, declarer: "north", contract: GameContract(8, .suit(.spades)))
        try forceWhist(engine: &engine, defenders: ["east", "south"])
        try playOut(engine: &engine, declarer: "north")

        guard case let .dealFinished(result) = engine.state, case .game = result.kind else {
            return XCTFail("Expected dealFinished.game; got \(engine.state.description).")
        }
        XCTAssertEqual(result.trickCounts["north"], 6,
                       "declarerFails must produce the exact trick count requested.")
        XCTAssertEqual(engine.score.pool["north"] ?? 0, 0,
                       "Failed contract must not credit pool.")
        XCTAssertGreaterThan(engine.score.mountain["north"] ?? 0, 0,
                             "Failed contract must charge mountain.")
    }

    // MARK: - cleanMisere

    func testCleanMisereRecipeYieldsZeroDeclarerTricks() throws {
        let recipe = HandRecipe.cleanMisere(declarer: "north")
        var engine = try PreferansEngine(players: activePlayers, firstDealer: "south")
        try engine.startDeal(deck: recipe.deck(for: activePlayers))

        _ = try engine.apply(.bid(player: "north", call: .bid(.misere)))
        _ = try engine.apply(.bid(player: "east", call: .pass))
        _ = try engine.apply(.bid(player: "south", call: .pass))

        try discardTalon(engine: &engine, declarer: "north")
        try playMisereLowest(engine: &engine, declarer: "north")

        guard case let .dealFinished(result) = engine.state, case .misere = result.kind else {
            return XCTFail("Expected dealFinished.misere; got \(engine.state.description).")
        }
        XCTAssertEqual(result.trickCounts["north"], 0,
                       "Clean misère recipe must produce zero declarer tricks.")
        XCTAssertEqual(engine.score.pool["north"], 10,
                       "Clean misère scores +10 pool.")
    }

    // MARK: - totusMakes (dedicated)

    func testTotusMakesUnderDedicatedPolicyCreditsBonusPool() throws {
        let recipe = HandRecipe.totusMakes(declarer: "north", strain: .suit(.spades))
        var engine = try PreferansEngine(
            players: activePlayers,
            match: MatchSettings(poolTarget: .max, totus: .dedicatedContract(requireWhist: true, bonusPool: 5)),
            firstDealer: "south"
        )
        try engine.startDeal(deck: recipe.deck(for: activePlayers))

        _ = try engine.apply(.bid(player: "north", call: .bid(.totus)))
        _ = try engine.apply(.bid(player: "east", call: .pass))
        _ = try engine.apply(.bid(player: "south", call: .pass))

        try discardTalon(engine: &engine, declarer: "north")
        _ = try engine.apply(.declareContract(player: "north", contract: GameContract(10, .suit(.spades))))
        try forceWhist(engine: &engine, defenders: ["east", "south"])
        try playOut(engine: &engine, declarer: "north")

        guard case let .dealFinished(result) = engine.state, case .game = result.kind else {
            return XCTFail("Expected dealFinished.game; got \(engine.state.description).")
        }
        XCTAssertEqual(result.trickCounts["north"], 10)
        // (10 - 5) * 2 = 10 contract value + 5 bonus = 15.
        XCTAssertEqual(engine.score.pool["north"], 15)
    }

    // MARK: - raspasyCleanExit

    func testRaspasyCleanExitYieldsZeroTricksForCleaner() throws {
        let recipe = HandRecipe.raspasyCleanExit(cleaner: "north", talonLeadSuit: nil)
        var engine = try PreferansEngine(players: activePlayers, firstDealer: "south")
        try engine.startDeal(deck: recipe.deck(for: activePlayers))

        for seat in activePlayers {
            _ = try engine.apply(.bid(player: seat, call: .pass))
        }
        try playRaspasyLowest(engine: &engine)

        guard case let .dealFinished(result) = engine.state, case .allPass = result.kind else {
            return XCTFail("Expected dealFinished.allPass; got \(engine.state.description).")
        }
        XCTAssertEqual(result.trickCounts["north"], 0,
                       "raspasy clean exit must take zero tricks for the cleaner.")
        XCTAssertGreaterThanOrEqual(engine.score.pool["north"] ?? 0, 1,
                                    "Cleaner must be credited the zero-trick pool bonus.")
    }

    func testRaspasyCleanExitWithTalonLeadSuitConstraint() throws {
        let recipe = HandRecipe.raspasyCleanExit(cleaner: "north", talonLeadSuit: .clubs)
        var engine = try PreferansEngine(
            players: activePlayers,
            rules: .sochiWithTalonLedAllPass,
            firstDealer: "south"
        )
        try engine.startDeal(deck: recipe.deck(for: activePlayers))

        for seat in activePlayers {
            _ = try engine.apply(.bid(player: seat, call: .pass))
        }
        guard case let .playing(state) = engine.state, case let .allPass(context) = state.kind else {
            return XCTFail("Expected all-pass play after three passes.")
        }
        XCTAssertEqual(context.talonPolicy, .leadSuitOnly)
        XCTAssertEqual(state.talon.count, 2)
        XCTAssertTrue(state.talon.allSatisfy { $0.suit == .clubs },
                      "talonLeadSuit constraint must place two clubs in the talon.")
    }

    // MARK: - Engine drivers

    /// Drives bidding so the named declarer wins the auction with the given
    /// bid; defenders pass. Caller is responsible for matching the active
    /// rotation to the engine's first-bidder ordering.
    private func driveAuctionWinning(engine: inout PreferansEngine, declarer: PlayerID, bid: ContractBid) throws {
        guard case let .bidding(state) = engine.state else {
            throw TestError("Expected bidding state at start of auction.")
        }
        for seat in state.activePlayers {
            if seat == declarer {
                _ = try engine.apply(.bid(player: seat, call: .bid(bid)))
            } else {
                _ = try engine.apply(.bid(player: seat, call: .pass))
            }
        }
    }

    private func discardTalon(engine: inout PreferansEngine, declarer: PlayerID) throws {
        guard case let .awaitingDiscard(exchange) = engine.state else {
            throw TestError("Expected awaitingDiscard; got \(engine.state.description).")
        }
        _ = try engine.apply(.discard(player: declarer, cards: exchange.talon))
    }

    private func declareContract(engine: inout PreferansEngine, declarer: PlayerID, contract: GameContract) throws {
        _ = try engine.apply(.declareContract(player: declarer, contract: contract))
    }

    private func forceWhist(engine: inout PreferansEngine, defenders: [PlayerID]) throws {
        guard case let .awaitingWhist(state) = engine.state else {
            throw TestError("Expected awaitingWhist; got \(engine.state.description).")
        }
        // Defenders in rotation order — engine picks the first defender after
        // the declarer; both whist to send the deal into closed-mode play.
        for defender in state.defenders {
            _ = try engine.apply(.whist(player: defender, call: .whist))
        }
        _ = defenders
    }

    /// Plays out a game contract: declarer plays highest legal each turn,
    /// defenders play lowest legal. Asserts no engine errors along the way.
    private func playOut(engine: inout PreferansEngine, declarer: PlayerID) throws {
        var safety = 64
        while case let .playing(state) = engine.state, safety > 0 {
            safety -= 1
            let actor = state.currentPlayer
            let card: Card?
            if actor == declarer {
                card = engine.legalCards(for: actor).max()
            } else {
                card = engine.legalCards(for: actor).min()
            }
            guard let card else {
                throw TestError("No legal card for \(actor) at trick \(state.completedTricks.count).")
            }
            _ = try engine.apply(.playCard(player: actor, card: card))
        }
    }

    /// Misère playout: declarer plays lowest legal (tries to dump everything),
    /// defenders also play lowest legal.
    private func playMisereLowest(engine: inout PreferansEngine, declarer: PlayerID) throws {
        var safety = 64
        while case let .playing(state) = engine.state, safety > 0 {
            safety -= 1
            let actor = state.currentPlayer
            guard let card = engine.legalCards(for: actor).min() else {
                throw TestError("No legal card for \(actor).")
            }
            _ = try engine.apply(.playCard(player: actor, card: card))
        }
    }

    /// All-pass playout: every seat plays lowest legal.
    private func playRaspasyLowest(engine: inout PreferansEngine) throws {
        var safety = 64
        while case let .playing(state) = engine.state, safety > 0 {
            safety -= 1
            let actor = state.currentPlayer
            guard let card = engine.legalCards(for: actor).min() else {
                throw TestError("No legal card for \(actor).")
            }
            _ = try engine.apply(.playCard(player: actor, card: card))
        }
    }
}

private struct TestError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
