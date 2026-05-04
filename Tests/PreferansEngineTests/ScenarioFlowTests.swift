import XCTest
@testable import PreferansApp
@testable import PreferansEngine

@MainActor
final class ScenarioFlowTests: XCTestCase {
    // MARK: - Helpers

    private func makeModel(scenario: DealScenario) throws -> GameViewModel {
        try GameViewModel(
            players: ["north", "east", "south"],
            rules: .sochi,
            firstDealer: "south",
            viewerPolicy: .pinned("north"),
            dealSource: ScriptedDealSource(decks: scenario.decks)
        )
    }

    private func bidding(_ model: GameViewModel) -> BiddingState? {
        if case let .bidding(state) = model.engine.state { return state }
        return nil
    }

    private func discardState(_ model: GameViewModel) -> ExchangeState? {
        if case let .awaitingDiscard(state) = model.engine.state { return state }
        return nil
    }

    private func contractState(_ model: GameViewModel) -> ContractDeclarationState? {
        if case let .awaitingContract(state) = model.engine.state { return state }
        return nil
    }

    private func whistState(_ model: GameViewModel) -> WhistState? {
        if case let .awaitingWhist(state) = model.engine.state { return state }
        return nil
    }

    private func playingState(_ model: GameViewModel) -> PlayingState? {
        if case let .playing(state) = model.engine.state { return state }
        return nil
    }

    private func dealResult(_ model: GameViewModel) -> DealResult? {
        if case let .dealFinished(result) = model.engine.state { return result }
        return nil
    }

    private static let sixSpades = ContractBid.game(GameContract(6, .suit(.spades)))
    private static let sixClubs = ContractBid.game(GameContract(6, .suit(.clubs)))

    /// Drives the auction prelude: north opens 6♠, east and south pass.
    /// Returns the resulting `awaitingDiscard` state, or fails the test.
    @discardableResult
    private func winSixSpadesAuction(_ model: GameViewModel, file: StaticString = #file, line: UInt = #line) -> ExchangeState? {
        model.send(.bid(player: "north", call: .bid(Self.sixSpades)))
        model.send(.bid(player: "east", call: .pass))
        model.send(.bid(player: "south", call: .pass))
        XCTAssertNil(model.lastError, file: file, line: line)
        guard let exchange = discardState(model) else {
            XCTFail("Expected awaitingDiscard after auction; got \(model.engine.state.description)", file: file, line: line)
            return nil
        }
        return exchange
    }

    /// Drives auction → talon discard → contract declaration → both whist,
    /// landing in `playing.game` with north as declarer and leader.
    @discardableResult
    private func progressToPlayInSixSpades(_ model: GameViewModel, file: StaticString = #file, line: UInt = #line) -> PlayingState? {
        guard let exchange = winSixSpadesAuction(model, file: file, line: line) else { return nil }
        model.send(.discard(player: "north", cards: exchange.talon))
        model.send(.declareContract(player: "north", contract: GameContract(6, .suit(.spades))))
        model.send(.whist(player: "east", call: .whist))
        model.send(.whist(player: "south", call: .whist))
        XCTAssertNil(model.lastError, file: file, line: line)
        guard let playing = playingState(model) else {
            XCTFail("Expected playing state; got \(model.engine.state.description)", file: file, line: line)
            return nil
        }
        return playing
    }

    // MARK: - Scenario integrity

    func testNorthSpadesSixScenarioDealsTheExpectedHandsAndTalon() throws {
        let model = try makeModel(scenario: .northBidsSpadesSix)
        model.startDeal()

        guard let bidding = bidding(model) else { return XCTFail("Expected bidding state") }
        XCTAssertEqual(bidding.dealer, "south")
        XCTAssertEqual(bidding.activePlayers, ["north", "east", "south"])
        XCTAssertEqual(bidding.currentPlayer, "north")
        XCTAssertEqual(bidding.talon, [Card(.diamonds, .jack), Card(.diamonds, .nine)],
                       "talon preserves deck order rather than being sorted")
        XCTAssertEqual(bidding.hands["north"]?.filter { $0.suit == .spades }.count, 6,
                       "north must hold six spades")
        XCTAssertEqual(bidding.hands["north"]?.contains(Card(.spades, .ace)), true)
        XCTAssertEqual(bidding.hands["east"]?.filter { $0.suit == .spades },
                       [Card(.spades, .seven), Card(.spades, .eight)])
        XCTAssertEqual(bidding.hands["south"]?.filter { $0.suit == .spades }, [])
    }

    func testNorthMisereScenarioDealsTopHalfToOpponents() throws {
        let model = try makeModel(scenario: .northBidsMisere)
        model.startDeal()

        guard let bidding = bidding(model) else { return XCTFail("Expected bidding state") }
        let northHand = bidding.hands["north"] ?? []
        XCTAssertTrue(northHand.allSatisfy { $0.rank.rawValue <= 9 },
                      "north's misère hand must contain no card above the 9")
        XCTAssertEqual(northHand.count, 10)
    }

    // MARK: - Bidding ladder

    func testNorthCanOpenAtSixSpadesAndOpponentsPass() throws {
        let model = try makeModel(scenario: .northBidsSpadesSix)
        model.startDeal()

        XCTAssertTrue(model.engine.legalBidCalls(for: "north").contains(.bid(Self.sixSpades)))

        guard let exchange = winSixSpadesAuction(model) else { return }
        XCTAssertEqual(exchange.declarer, "north")
        XCTAssertEqual(exchange.finalBid, Self.sixSpades)
        XCTAssertEqual(exchange.hands["north"]?.count, 10,
                       "talon is presented separately until the discard")
        XCTAssertEqual(exchange.talon.count, 2)
    }

    // MARK: - Discard, contract declaration

    func testDiscardingTwoCardsAdvancesToContractDeclaration() throws {
        let model = try makeModel(scenario: .northBidsSpadesSix)
        model.startDeal()
        guard let exchange = winSixSpadesAuction(model) else { return }

        let toDiscard = exchange.talon
        model.send(.discard(player: "north", cards: toDiscard))

        XCTAssertNil(model.lastError)
        guard let contract = contractState(model) else {
            return XCTFail("Expected awaitingContract; got \(model.engine.state.description)")
        }
        XCTAssertEqual(contract.declarer, "north")
        XCTAssertEqual(contract.discard, toDiscard)
        XCTAssertEqual(contract.hands["north"]?.count, 10)
    }

    // MARK: - Whist passed-out happy path

    func testBothDefendersPassClosesTheDealAtContractValue() throws {
        let model = try makeModel(scenario: .northBidsSpadesSix)
        model.startDeal()

        model.send(.bid(player: "north", call: .bid(Self.sixClubs)))
        model.send(.bid(player: "east", call: .pass))
        model.send(.bid(player: "south", call: .pass))

        XCTAssertNil(model.lastError)
        guard let exchange = discardState(model) else {
            return XCTFail("Expected awaitingDiscard after auction; got \(model.engine.state.description)")
        }

        model.send(.discard(player: "north", cards: exchange.talon))
        model.send(.declareContract(player: "north", contract: GameContract(6, .suit(.clubs))))
        model.send(.whist(player: "east", call: .pass))
        model.send(.whist(player: "south", call: .pass))

        XCTAssertNil(model.lastError)
        guard let result = dealResult(model), case .passedOut = result.kind else {
            return XCTFail("Expected passed-out result; got \(model.engine.state.description)")
        }
        XCTAssertEqual(model.engine.score.pool["north"], 2,
                       "GameContract.value = (tricks - 5) * 2; 6♣ scores 2 to pool")
        XCTAssertEqual(model.engine.score.pool["east"] ?? 0, 0)
        XCTAssertEqual(model.engine.score.pool["south"] ?? 0, 0)
    }

    // MARK: - Whist play-through

    func testBothDefendersWhistAndPlayBeginsWithDeclarerLeading() throws {
        let model = try makeModel(scenario: .northBidsSpadesSix)
        model.startDeal()
        guard let playing = progressToPlayInSixSpades(model) else { return }

        XCTAssertEqual(playing.leader, "north")
        XCTAssertEqual(playing.currentPlayer, "north")
        XCTAssertTrue(playing.currentTrick.isEmpty)
    }

    func testFirstTrickIsWonByLeadAceOfTrumpsAndRotatesLead() throws {
        let model = try makeModel(scenario: .northBidsSpadesSix)
        model.startDeal()
        guard progressToPlayInSixSpades(model) != nil else { return }

        model.send(.playCard(player: "north", card: Card(.spades, .ace)))
        model.send(.playCard(player: "east", card: Card(.spades, .seven)))
        model.send(.playCard(player: "south", card: Card(.clubs, .seven)))
        XCTAssertNil(model.lastError)

        guard let playing = playingState(model) else {
            return XCTFail("Expected to remain in playing state after one trick")
        }
        XCTAssertEqual(playing.completedTricks.count, 1)
        XCTAssertEqual(playing.completedTricks.first?.winner, "north")
        XCTAssertEqual(playing.currentPlayer, "north", "trick winner leads next")
        XCTAssertEqual(playing.trickCounts["north"], 1)
    }

    // MARK: - Misère path

    func testMisereIsLegalOnOpeningAndOpponentsPass() throws {
        let model = try makeModel(scenario: .northBidsMisere)
        model.startDeal()

        XCTAssertTrue(model.engine.legalBidCalls(for: "north").contains(.bid(.misere)))

        model.send(.bid(player: "north", call: .bid(.misere)))
        model.send(.bid(player: "east", call: .pass))
        model.send(.bid(player: "south", call: .pass))

        XCTAssertNil(model.lastError)
        // Misère also opens a discard window (declarer picks up the talon).
        guard let exchange = discardState(model) else {
            return XCTFail("Expected awaitingDiscard after misère wins; got \(model.engine.state.description)")
        }
        XCTAssertEqual(exchange.declarer, "north")
        XCTAssertEqual(exchange.finalBid, .misere)
    }

    // MARK: - Full play-through to dealFinished

    func testPlayingEverySpadeFromTheTopWinsTenTricksAndScoresTheContract() throws {
        let model = try makeModel(scenario: .northBidsSpadesSix)
        model.startDeal()
        guard progressToPlayInSixSpades(model) != nil else { return }

        XCTAssertTrue(GameViewModelTestDriver.playOutCurrentDeal(model, policy: .highestLegal))

        guard let result = dealResult(model), case .game = result.kind else {
            return XCTFail("Expected dealFinished.game; got \(model.engine.state.description)")
        }
        XCTAssertEqual(result.trickCounts["north"], 10,
                       "north's hand is unbeatable: 6 top spades + ♣A,♣K,♥A,♦A wins every trick")
        XCTAssertGreaterThan(model.engine.score.pool["north"] ?? 0, 0)
    }

    // MARK: - Misère play-out

    func testMiserePlayOutEndsAtDealFinishedWithMisereResult() throws {
        let model = try makeModel(scenario: .northBidsMisere)
        model.startDeal()

        model.send(.bid(player: "north", call: .bid(.misere)))
        model.send(.bid(player: "east", call: .pass))
        model.send(.bid(player: "south", call: .pass))

        guard let exchange = discardState(model) else { return XCTFail("Expected discard") }
        // Discard the talon's two cards (♥10, ♦10) — north's hand stays at the
        // bottom-of-suit baseline so the misère is at least defensible.
        model.send(.discard(player: "north", cards: exchange.talon))

        // Misère skips contract declaration and whist — straight to play.
        guard let playing = playingState(model), case .misere = playing.kind else {
            return XCTFail("Expected playing.misere immediately after misère discard; got \(model.engine.state.description)")
        }
        XCTAssertEqual(playing.leader, "north")

        // Drive every turn with the lowest legal card. North as declarer plays
        // its lowest in an attempt at a clean misère; the defenders likewise
        // play their lowest, which is the simplest deterministic strategy.
        XCTAssertTrue(GameViewModelTestDriver.playOutCurrentDeal(model, policy: .lowestLegal))
        XCTAssertNil(model.lastError)

        guard let result = dealResult(model), case .misere = result.kind else {
            return XCTFail("Expected dealFinished.misere; got \(model.engine.state.description)")
        }
        XCTAssertEqual(result.completedTricks.count, 10, "every misère deal plays out 10 tricks")

        let northTricks = result.trickCounts["north"] ?? 0
        if northTricks == 0 {
            XCTAssertEqual(model.engine.score.pool["north"], 10,
                           "clean misère scores +10 to declarer's pool")
            XCTAssertEqual(model.engine.score.mountain["north"] ?? 0, 0)
        } else {
            XCTAssertEqual(model.engine.score.pool["north"] ?? 0, 0,
                           "failed misère scores no pool")
            XCTAssertEqual(model.engine.score.mountain["north"], 10 * northTricks,
                           "failed misère charges 10 per trick to declarer's mountain")
        }
    }

    // MARK: - 4-player rotation across multiple deals

    func testFourPlayerDealerAndSitOutRotateAcrossFourConsecutiveDeals() throws {
        let model = try GameViewModel(
            players: ["north", "east", "south", "west"],
            rules: .sochi,
            firstDealer: "north",
            viewerPolicy: .pinned("north"),
            dealSource: ScriptedDealSource(decks: [Deck.standard32])
        )

        let expectedDealers: [PlayerID] = ["north", "east", "south", "west"]
        var observedDealers: [PlayerID] = []
        var observedActiveSets: [[PlayerID]] = []

        for _ in 0..<expectedDealers.count {
            model.startDeal()
            guard let bidding = bidding(model) else {
                return XCTFail("Expected bidding state at start of deal; got \(model.engine.state.description)")
            }
            observedDealers.append(bidding.dealer)
            observedActiveSets.append(bidding.activePlayers)

            // All three active players pass to short-circuit to all-pass play.
            for active in bidding.activePlayers {
                model.send(.bid(player: active, call: .pass))
            }
            // Play out the all-pass deal so the engine returns to dealFinished.
            XCTAssertTrue(GameViewModelTestDriver.playOutCurrentDeal(model, policy: .lowestLegal),
                          "all-pass play-out should advance to dealFinished")
            XCTAssertNotNil(dealResult(model),
                            "engine must reach dealFinished before next deal can start")
        }

        XCTAssertEqual(observedDealers, expectedDealers,
                       "dealer must rotate through every player exactly once")

        // The dealer always sits out — verify the four sit-out rosters are the
        // four players in the same rotation.
        let sitOuts = zip(observedDealers, observedActiveSets).map { dealer, active -> PlayerID in
            let allSeats: Set<PlayerID> = ["north", "east", "south", "west"]
            return allSeats.subtracting(active).first ?? dealer
        }
        XCTAssertEqual(sitOuts, expectedDealers,
                       "the sat-out player on each deal must be that deal's dealer")
        XCTAssertEqual(Set(sitOuts), Set(expectedDealers),
                       "every player must sit out exactly once over four deals")
    }

    func testEastCannotSluffWhenHoldingALeadSuitCard() throws {
        let model = try makeModel(scenario: .northBidsSpadesSix)
        model.startDeal()
        guard progressToPlayInSixSpades(model) != nil else { return }

        model.send(.playCard(player: "north", card: Card(.spades, .ace)))
        XCTAssertNil(model.lastError)

        model.send(.playCard(player: "east", card: Card(.clubs, .jack)))
        XCTAssertNotNil(model.lastError, "engine should reject an illegal sluff")

        model.send(.playCard(player: "east", card: Card(.spades, .seven)))
        XCTAssertNil(model.lastError, "east should be able to recover with a legal spade")
    }
}
