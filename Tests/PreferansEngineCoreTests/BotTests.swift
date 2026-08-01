import XCTest
@testable import PreferansEngine
@testable import PreferansEngineTestSupport

/// Verifies the bot can drive every phase of every contract variant from
/// the dealt-cards state through to a scored result, without ever picking
/// an illegal action.
final class BotTests: XCTestCase {
    private let players: [PlayerID] = ["N", "E", "S"]

    private enum OpeningExpectation {
        case exact(BidCall)
        case gameLevel(Int)
    }

    private struct OpeningScenario {
        var name: String
        var hand: [Card]
        var profile: BotProfile
        var precedingAllPassDeals: Int
        var expectation: OpeningExpectation
    }

    func testDifficultyControlsPlannerDepth() {
        XCTAssertEqual(
            HeuristicStrategy(profile: BotProfile(difficulty: .casual)).planner.samples,
            6
        )
        XCTAssertEqual(
            HeuristicStrategy(profile: BotProfile(difficulty: .seasoned)).planner.samples,
            16
        )
        XCTAssertEqual(
            HeuristicStrategy(profile: BotProfile(difficulty: .expert)).planner.samples,
            32
        )
    }

    func testDifficultyCorpusChangesAuctionRiskWithoutChangingLegality() async throws {
        let borderline = cards(.spades, [.ace, .king])
            + cards(.clubs, [.ace, .eight, .nine])
            + cards(.diamonds, [.king, .seven])
            + cards(.hearts, [.nine, .ten, .jack])
        let engine = try makeBiddingEngine(
            northHand: borderline,
            precedingAllPassDeals: 0
        )

        for difficulty in BotDifficulty.allCases {
            let strategy = HeuristicStrategy(
                profile: BotProfile(difficulty: difficulty, temperament: .adaptive),
                planner: CardPlayPlanner(samples: 1)
            )
            let action = await strategy.decide(snapshot: engine.snapshot, viewer: "N")
            guard case let .bid(player, call) = action else {
                return XCTFail("\(difficulty.rawValue): expected a bidding action")
            }
            XCTAssertEqual(player, "N", difficulty.rawValue)
            XCTAssertTrue(
                engine.legalBidCalls(for: "N").contains(call),
                "\(difficulty.rawValue) proposed an illegal call"
            )
            switch difficulty {
            case .casual:
                XCTAssertEqual(call, .pass, difficulty.rawValue)
            case .seasoned, .expert:
                guard case let .bid(.game(contract)) = call else {
                    return XCTFail("\(difficulty.rawValue) should accept the borderline six")
                }
                XCTAssertEqual(contract.tricks, 6)
            }
        }
    }

    func testCardPlayTemperamentCorpusBalancesReliabilityAndUpside() {
        struct Scenario {
            var name: String
            var stable: [Double]
            var swing: [Double]
            var expected: [BotTemperament: Card]
        }

        let stableCard = Card(.spades, .seven)
        let swingCard = Card(.spades, .ace)
        let planner = CardPlayPlanner(samples: 3)
        let scenarios = [
            Scenario(
                name: "controlled upside separates all three profiles",
                stable: [4, 4, 4],
                swing: [0, 0, 10],
                expected: [.careful: stableCard, .adaptive: stableCard, .bold: swingCard]
            ),
            Scenario(
                name: "reckless downside is rejected even by bold play",
                stable: [4, 4, 4],
                swing: [0, 0, 6],
                expected: [.careful: stableCard, .adaptive: stableCard, .bold: stableCard]
            ),
            Scenario(
                name: "equal lines preserve honors unless the profile is bold",
                stable: [3, 3, 3],
                swing: [3, 3, 3],
                expected: [.careful: stableCard, .adaptive: stableCard, .bold: swingCard]
            )
        ]

        for scenario in scenarios {
            for temperament in BotTemperament.allCases {
                XCTAssertEqual(
                    planner.selectCard(
                        legal: [stableCard, swingCard],
                        outcomes: [scenario.stable, scenario.swing],
                        temperament: temperament
                    ),
                    scenario.expected[temperament],
                    "\(scenario.name): \(temperament.rawValue)"
                )
            }
        }
    }

    func testOpeningDecisionCorpusCoversStrengthStyleAndRaspasyExit() async throws {
        let strongSpades = cards(.spades, Rank.allCases)
            + cards(.clubs, [.ace])
            + cards(.hearts, [.ace])
        let cleanMisere = cards(.spades, [.seven, .eight, .nine])
            + cards(.clubs, [.seven, .eight])
            + cards(.diamonds, [.seven, .eight])
            + cards(.hearts, [.seven, .eight, .nine])
        let deadMiddles = cards(.spades, [.nine, .ten, .jack])
            + cards(.clubs, [.nine, .ten, .jack])
            + cards(.diamonds, [.nine, .ten])
            + cards(.hearts, [.nine, .ten])
        let borderline = cards(.spades, [.ace, .king])
            + cards(.clubs, [.ace, .eight, .nine])
            + cards(.diamonds, [.king, .seven])
            + cards(.hearts, [.nine, .ten, .jack])

        let scenarios = [
            OpeningScenario(
                name: "obvious six-spade opener",
                hand: strongSpades,
                profile: .standard,
                precedingAllPassDeals: 0,
                expectation: .exact(.bid(.game(GameContract(6, .suit(.spades)))))
            ),
            OpeningScenario(
                name: "clean low-card misere",
                hand: cleanMisere,
                profile: .standard,
                precedingAllPassDeals: 0,
                expectation: .exact(.bid(.misere))
            ),
            OpeningScenario(
                name: "neither a game nor a misere",
                hand: deadMiddles,
                profile: .standard,
                precedingAllPassDeals: 0,
                expectation: .exact(.pass)
            ),
            OpeningScenario(
                name: "careful profile declines a borderline six",
                hand: borderline,
                profile: BotProfile(difficulty: .seasoned, temperament: .careful),
                precedingAllPassDeals: 0,
                expectation: .exact(.pass)
            ),
            OpeningScenario(
                name: "bold profile accepts the same borderline six",
                hand: borderline,
                profile: BotProfile(difficulty: .seasoned, temperament: .bold),
                precedingAllPassDeals: 0,
                expectation: .gameLevel(6)
            ),
            OpeningScenario(
                name: "strict third-stage raspasy exit starts at eight",
                hand: strongSpades,
                profile: .standard,
                precedingAllPassDeals: 2,
                expectation: .exact(.bid(.game(GameContract(8, .suit(.spades)))))
            ),
        ]

        for scenario in scenarios {
            let engine = try makeBiddingEngine(
                northHand: scenario.hand,
                precedingAllPassDeals: scenario.precedingAllPassDeals
            )
            let strategy = HeuristicStrategy(
                profile: scenario.profile,
                planner: CardPlayPlanner(samples: 1)
            )
            let action = await strategy.decide(snapshot: engine.snapshot, viewer: "N")
            guard case let .bid(player, call) = action else {
                XCTFail("\(scenario.name): expected a bidding action, got \(String(describing: action))")
                continue
            }

            XCTAssertEqual(player, "N", scenario.name)
            XCTAssertTrue(engine.legalBidCalls(for: "N").contains(call), scenario.name)
            switch scenario.expectation {
            case let .exact(expected):
                XCTAssertEqual(call, expected, scenario.name)
            case let .gameLevel(expectedLevel):
                guard case let .bid(.game(contract)) = call else {
                    XCTFail("\(scenario.name): expected a game bid, got \(call)")
                    continue
                }
                XCTAssertEqual(contract.tricks, expectedLevel, scenario.name)
            }
        }
    }

    func testWeakHighContractUsesWithoutThreeConcession() async throws {
        let weakHand = cards(.spades, [.seven, .eight, .nine, .ten])
            + cards(.clubs, [.seven, .eight, .nine])
            + cards(.diamonds, [.seven, .eight, .nine])
        let engine = try makeContractDeclarationEngine(
            hand: weakHand,
            finalBid: .game(GameContract(8, .suit(.spades)))
        )
        let strategy = HeuristicStrategy(
            profile: BotProfile(difficulty: .casual, temperament: .careful),
            planner: CardPlayPlanner(samples: 1)
        )

        let action = await strategy.decide(snapshot: engine.snapshot, viewer: "N")

        XCTAssertEqual(action, .concedeWithoutThree(player: "N"))
    }

    func testStrongHighContractStillDeclaresNormally() async throws {
        let strongHand = cards(.spades, Rank.allCases)
            + cards(.clubs, [.ace])
            + cards(.hearts, [.ace])
        let engine = try makeContractDeclarationEngine(
            hand: strongHand,
            finalBid: .game(GameContract(8, .suit(.spades)))
        )
        let strategy = HeuristicStrategy(
            profile: BotProfile(difficulty: .expert, temperament: .bold),
            planner: CardPlayPlanner(samples: 1)
        )

        let action = await strategy.decide(snapshot: engine.snapshot, viewer: "N")

        guard case let .declareContract(player, contract) = action else {
            return XCTFail("Strong high contract should be declared, got \(String(describing: action))")
        }
        XCTAssertEqual(player, "N")
        XCTAssertGreaterThanOrEqual(contract.tricks, 8)
    }

    func testMisereDiscardCorpusDropsTheTwoTalonHonors() async throws {
        var engine = try PreferansEngine(players: players, firstDealer: "S")
        _ = try engine.startDeal(deck: makeDeck(.misereForNorth))
        _ = try engine.apply(.bid(player: "N", call: .bid(.misere)))
        _ = try engine.apply(.bid(player: "E", call: .pass))
        _ = try engine.apply(.bid(player: "S", call: .pass))

        let strategy = HeuristicStrategy(planner: CardPlayPlanner(samples: 1))
        let proposed = await strategy.decide(snapshot: engine.snapshot, viewer: "N")
        guard let action = proposed,
              case let .discard(player, discarded) = action else {
            return XCTFail("Expected the misere declarer to discard, got \(String(describing: proposed))")
        }

        XCTAssertEqual(player, "N")
        XCTAssertEqual(Set(discarded), Set(cards(.hearts, [.king, .ace])))
        XCTAssertNoThrow(try engine.apply(action))
    }

    func testGameDiscardScoresAgainstDeclaredTrump() async throws {
        let north = cards(.clubs, [.seven, .queen, .ace])
            + cards(.diamonds, [.nine, .jack])
            + cards(.spades, [.seven, .ace])
            + cards(.hearts, [.seven, .nine, .ten])
        let talon = cards(.hearts, [.queen]) + cards(.diamonds, [.queen])
        let used = Set(north + talon)
        let remaining = Deck.standard32.filter { !used.contains($0) }
        let exchange = ExchangeState(
            dealer: "S",
            activePlayers: players,
            hands: [
                "N": north,
                "E": Array(remaining.prefix(10)),
                "S": Array(remaining.dropFirst(10).prefix(10))
            ],
            talon: talon,
            declarer: "N",
            finalBid: .game(GameContract(6, .suit(.spades))),
            auction: []
        )
        let snapshot = PreferansSnapshot(
            players: players,
            rules: .sochi,
            state: .awaitingDiscard(exchange),
            score: ScoreSheet(players: players),
            nextDealer: "E"
        )
        let engine = try PreferansEngine(snapshot: snapshot)
        let strategy = HeuristicStrategy(planner: CardPlayPlanner(samples: 1))

        let action = await strategy.decide(snapshot: engine.snapshot, viewer: "N")

        guard case let .discard(player, discarded) = action else {
            return XCTFail("Expected a game discard, got \(String(describing: action))")
        }
        XCTAssertEqual(player, "N")
        XCTAssertEqual(Set(discarded), Set(cards(.hearts, [.seven]) + cards(.spades, [.seven])))
    }

    func testDefenderRolloutTakesCheapestWinningCard() {
        let planner = CardPlayPlanner(samples: 1)
        let state = rolloutState(
            currentPlayer: "N",
            currentTrick: [CardPlay(player: "E", card: Card(.hearts, .ten))]
        )

        let choice = planner.greedyChoice(
            legal: [Card(.hearts, .ace), Card(.hearts, .jack)],
            playing: state,
            actor: "N"
        )

        XCTAssertEqual(choice, Card(.hearts, .jack))
    }

    func testDefenderRolloutDoesNotOvertakeWinningPartner() {
        let planner = CardPlayPlanner(samples: 1)
        let state = rolloutState(
            currentPlayer: "N",
            currentTrick: [
                CardPlay(player: "E", card: Card(.hearts, .ten)),
                CardPlay(player: "S", card: Card(.hearts, .king))
            ]
        )

        let choice = planner.greedyChoice(
            legal: [Card(.hearts, .ace), Card(.hearts, .queen)],
            playing: state,
            actor: "N"
        )

        XCTAssertEqual(choice, Card(.hearts, .queen))
    }

    func testMisereDeclarerRolloutShedsHighestLosingCard() {
        let planner = CardPlayPlanner(samples: 1)
        let state = rolloutState(
            currentPlayer: "N",
            currentTrick: [CardPlay(player: "E", card: Card(.hearts, .ten))],
            kind: .misere(MiserePlayContext(declarer: "N"))
        )

        let choice = planner.greedyChoice(
            legal: [Card(.hearts, .seven), Card(.hearts, .nine)],
            playing: state,
            actor: "N"
        )

        XCTAssertEqual(choice, Card(.hearts, .nine))
    }

    func testMisereDefenderRolloutTakesCheapestWinningCard() {
        let planner = CardPlayPlanner(samples: 1)
        let state = rolloutState(
            currentPlayer: "N",
            currentTrick: [CardPlay(player: "E", card: Card(.hearts, .ten))],
            kind: .misere(MiserePlayContext(declarer: "E"))
        )

        let choice = planner.greedyChoice(
            legal: [Card(.hearts, .ace), Card(.hearts, .jack)],
            playing: state,
            actor: "N"
        )

        XCTAssertEqual(choice, Card(.hearts, .jack))
    }

    func testMisereDefenderRolloutDoesNotOvertakeWinningPartner() {
        let planner = CardPlayPlanner(samples: 1)
        let state = rolloutState(
            currentPlayer: "N",
            currentTrick: [
                CardPlay(player: "E", card: Card(.hearts, .ten)),
                CardPlay(player: "S", card: Card(.hearts, .king))
            ],
            kind: .misere(MiserePlayContext(declarer: "E"))
        )

        let choice = planner.greedyChoice(
            legal: [Card(.hearts, .ace), Card(.hearts, .queen)],
            playing: state,
            actor: "N"
        )

        XCTAssertEqual(choice, Card(.hearts, .queen))
    }

    func testStrategyDrivesEntireGameDealToFinish() async throws {
        let strategy = HeuristicStrategy(planner: CardPlayPlanner(samples: 6))
        let outcome = try await playOneDeal(strategy: strategy, deck: makeDeck(.strongSpades))
        XCTAssertNotNil(outcome.result)
        switch outcome.result?.kind {
        case .game, .halfWhist, .passedOut, .withoutThree, .misere:
            break
        default:
            XCTFail("Unexpected deal result: \(String(describing: outcome.result?.kind))")
        }
    }

    func testEveryTemperamentCompletesTheSameFixedGameDealLegally() async throws {
        for temperament in BotTemperament.allCases {
            let strategy = HeuristicStrategy(
                profile: BotProfile(difficulty: .casual, temperament: temperament),
                planner: CardPlayPlanner(samples: 6)
            )
            let outcome = try await playOneDeal(strategy: strategy, deck: makeDeck(.strongSpades))

            XCTAssertNotNil(outcome.result, temperament.rawValue)
            XCTAssertGreaterThan(outcome.stepCount, 0, temperament.rawValue)
        }
    }

    func testStrategyDrivesMisereDealToFinish() async throws {
        let strategy = HeuristicStrategy(planner: CardPlayPlanner(samples: 6))
        let outcome = try await playOneDeal(strategy: strategy, deck: makeDeck(.misereForNorth))
        XCTAssertNotNil(outcome.result)
    }

    func testStrategyDrivesAllPassDealToFinish() async throws {
        let strategy = HeuristicStrategy(planner: CardPlayPlanner(samples: 4))
        let outcome = try await playOneDeal(strategy: strategy, deck: makeDeck(.allWeak))
        XCTAssertNotNil(outcome.result)
    }

    func testFiveConsecutiveBotDealsAllReachAScoredResult() async throws {
        let strategy = HeuristicStrategy(planner: CardPlayPlanner(samples: 4))
        var engine = try PreferansEngine(players: players)
        for dealIndex in 0..<5 {
            _ = try engine.startDeal(deck: Deck.standard32.shuffled())
            let drive = try await BotTestDriver.drive(engine: &engine, strategy: strategy)
            XCTAssertFalse(drive.stalled, "Bot strategy stalled on deal \(dealIndex) after \(drive.steps) steps.")
            switch engine.state {
            case .dealFinished, .gameOver:
                break
            default:
                return XCTFail("Deal \(dealIndex) did not reach a finished state: \(engine.state.description)")
            }
            if case .gameOver = engine.state { break }
        }
    }

    func testSecondDefenderPassesMarginalHandAfterFirstDefenderWhists() async throws {
        let strategy = HeuristicStrategy(planner: CardPlayPlanner(samples: 1))
        let engine = try makeSecondDefenderWhistEngine(
            secondDefenderHand: [
                Card(.spades, .ace),
                Card(.diamonds, .ace),
                Card(.spades, .seven),
                Card(.spades, .eight),
                Card(.clubs, .seven),
                Card(.clubs, .eight),
                Card(.diamonds, .seven),
                Card(.diamonds, .eight),
                Card(.hearts, .seven),
                Card(.hearts, .eight)
            ]
        )

        let action = await strategy.decide(snapshot: engine.snapshot, viewer: "S")

        XCTAssertEqual(action, .whist(player: "S", call: .pass),
                       "after a first defender has whisted, a marginal second defender should leave the hand open/single-whistable")
    }

    func testSecondDefenderStillWhistsWithStrongHandAfterFirstDefenderWhists() async throws {
        let strategy = HeuristicStrategy(planner: CardPlayPlanner(samples: 1))
        let engine = try makeSecondDefenderWhistEngine(
            secondDefenderHand: strongSecondDefenderHand
        )

        let action = await strategy.decide(snapshot: engine.snapshot, viewer: "S")

        XCTAssertEqual(action, .whist(player: "S", call: .whist),
                       "a genuinely strong second defender should still be willing to whist")
    }

    func testTemperamentChangesBorderlineSecondWhist() async throws {
        let engine = try makeSecondDefenderWhistEngine(secondDefenderHand: strongSecondDefenderHand)
        let careful = HeuristicStrategy(
            profile: BotProfile(difficulty: .seasoned, temperament: .careful),
            planner: CardPlayPlanner(samples: 1)
        )
        let bold = HeuristicStrategy(
            profile: BotProfile(difficulty: .seasoned, temperament: .bold),
            planner: CardPlayPlanner(samples: 1)
        )

        let carefulAction = await careful.decide(snapshot: engine.snapshot, viewer: "S")
        let boldAction = await bold.decide(snapshot: engine.snapshot, viewer: "S")

        XCTAssertEqual(carefulAction, .whist(player: "S", call: .pass))
        XCTAssertEqual(boldAction, .whist(player: "S", call: .whist))
    }

    func testTemperamentChangesSingleWhistVisibility() async throws {
        var engine = try makeSecondDefenderWhistEngine(
            secondDefenderHand: [
                Card(.spades, .ace), Card(.diamonds, .ace),
                Card(.spades, .seven), Card(.spades, .eight),
                Card(.clubs, .seven), Card(.clubs, .eight),
                Card(.diamonds, .seven), Card(.diamonds, .eight),
                Card(.hearts, .seven), Card(.hearts, .eight)
            ]
        )
        _ = try engine.apply(.whist(player: "S", call: .pass))
        let careful = HeuristicStrategy(
            profile: BotProfile(difficulty: .seasoned, temperament: .careful),
            planner: CardPlayPlanner(samples: 1)
        )
        let bold = HeuristicStrategy(
            profile: BotProfile(difficulty: .seasoned, temperament: .bold),
            planner: CardPlayPlanner(samples: 1)
        )

        let carefulAction = await careful.decide(snapshot: engine.snapshot, viewer: "E")
        let boldAction = await bold.decide(snapshot: engine.snapshot, viewer: "E")

        XCTAssertEqual(carefulAction, .chooseDefenderMode(player: "E", mode: .open))
        XCTAssertEqual(boldAction, .chooseDefenderMode(player: "E", mode: .closed))
    }

    func testStrategicDecisionCarriesPublicSafeProfileExplanation() async throws {
        let profile = BotProfile(difficulty: .expert, temperament: .bold)
        let strategy = HeuristicStrategy(
            profile: profile,
            planner: CardPlayPlanner(samples: 1)
        )
        let engine = try makeSecondDefenderWhistEngine(
            secondDefenderHand: strongSecondDefenderHand
        )

        let proposed = await strategy.decision(snapshot: engine.snapshot, viewer: "S")
        let decision = try XCTUnwrap(proposed)

        XCTAssertEqual(decision.action, .whist(player: "S", call: .whist))
        XCTAssertEqual(
            decision.explanation,
            BotDecisionExplanation(actor: "S", profile: profile, rationale: .fullWhist)
        )
        XCTAssertEqual(decision.explanation?.rationale.category, .whist)
    }

    // MARK: - Driver

    private struct DealOutcome {
        var result: DealResult?
        var stepCount: Int
    }

    private func playOneDeal(strategy: PlayerStrategy, deck: [Card]) async throws -> DealOutcome {
        // First dealer = "S" so the active rotation is [N, E, S] — what
        // makeDeck assumes when laying out cards.
        var engine = try PreferansEngine(players: players, firstDealer: "S")
        _ = try engine.startDeal(deck: deck)
        let drive = try await BotTestDriver.drive(engine: &engine, strategy: strategy)
        if drive.stalled {
            XCTFail("Strategy stalled in \(engine.state.description) after \(drive.steps) steps.")
        }
        var result: DealResult? = nil
        switch engine.state {
        case let .dealFinished(r): result = r
        case let .gameOver(s): result = s.lastDeal
        default: break
        }
        return DealOutcome(result: result, stepCount: drive.steps)
    }

    private func makeBiddingEngine(
        northHand: [Card],
        precedingAllPassDeals: Int
    ) throws -> PreferansEngine {
        XCTAssertEqual(northHand.count, 10)
        XCTAssertEqual(Set(northHand).count, 10)
        let remaining = Deck.standard32.filter { !northHand.contains($0) }
        XCTAssertEqual(remaining.count, 22)
        let east = Array(remaining.prefix(10))
        let south = Array(remaining.dropFirst(10).prefix(10))
        let talon = Array(remaining.suffix(2))

        var engine = try PreferansEngine(players: players, firstDealer: "S")
        _ = try engine.startDeal(
            deck: assemble(north: northHand, east: east, south: south, talon: talon)
        )
        guard precedingAllPassDeals > 0 else { return engine }

        var snapshot = engine.snapshot
        // The fixture is an active deal preceded by this many scored
        // raspasy deals, so keep the history counter pair internally
        // consistent when rehydrating it.
        snapshot.dealsPlayed = precedingAllPassDeals
        snapshot.consecutiveAllPassDeals = precedingAllPassDeals
        return try PreferansEngine(snapshot: snapshot)
    }

    private func rolloutState(
        currentPlayer: PlayerID,
        currentTrick: [CardPlay],
        kind: PlayKind? = nil
    ) -> PlayingState {
        PlayingState(
            dealer: "S",
            activePlayers: players,
            hands: players.dictionary(filledWith: []),
            talon: [],
            leader: "E",
            currentPlayer: currentPlayer,
            currentTrick: currentTrick,
            kind: kind ?? .game(GamePlayContext(
                declarer: "E",
                contract: GameContract(6, .suit(.clubs)),
                defenders: ["N", "S"],
                whisters: ["N", "S"],
                defenderPlayMode: .closed,
                whistCalls: []
            ))
        )
    }

    // MARK: - Deck stacking helpers

    private enum DealerPattern {
        case strongSpades, misereForNorth, allWeak
    }

    private var strongSecondDefenderHand: [Card] {
        [
            Card(.spades, .ace),
            Card(.diamonds, .ace),
            Card(.clubs, .king),
            Card(.clubs, .queen),
            Card(.clubs, .jack),
            Card(.clubs, .seven),
            Card(.spades, .seven),
            Card(.spades, .eight),
            Card(.diamonds, .seven),
            Card(.hearts, .seven)
        ]
    }

    private func cards(_ suit: Suit, _ ranks: [Rank]) -> [Card] {
        ranks.map { Card(suit, $0) }
    }

    private func makeDeck(_ pattern: DealerPattern) -> [Card] {
        switch pattern {
        case .strongSpades:
            return assemble(
                north: cards(.spades, Rank.allCases) + cards(.clubs, [.ace]) + cards(.hearts, [.ace]),
                east: cards(.clubs, [.king, .queen, .jack, .ten, .nine, .eight, .seven])
                    + cards(.hearts, [.queen, .jack, .ten]),
                south: cards(.diamonds, Rank.allCases) + cards(.hearts, [.nine, .eight]),
                talon: cards(.hearts, [.seven, .king])
            )
        case .misereForNorth:
            return assemble(
                north: cards(.spades, [.seven, .eight, .nine])
                    + cards(.clubs, [.seven, .eight])
                    + cards(.diamonds, [.seven, .eight])
                    + cards(.hearts, [.seven, .eight, .nine]),
                east: cards(.spades, [.ten, .jack, .queen]) + cards(.clubs, [.nine, .ten, .jack, .queen])
                    + cards(.diamonds, [.nine, .ten, .jack]),
                south: cards(.spades, [.king, .ace]) + cards(.clubs, [.king, .ace])
                    + cards(.diamonds, [.queen, .king, .ace]) + cards(.hearts, [.ten, .jack, .queen]),
                talon: cards(.hearts, [.king, .ace])
            )
        case .allWeak:
            return assemble(
                north: cards(.spades, [.seven, .eight, .nine, .ten])
                    + cards(.clubs, [.seven, .eight, .nine])
                    + cards(.diamonds, [.seven, .eight, .nine]),
                east: cards(.spades, [.jack]) + cards(.clubs, [.ten, .jack, .queen, .king])
                    + cards(.diamonds, [.ten, .jack, .queen, .king, .ace]),
                south: cards(.spades, [.queen, .king, .ace])
                    + cards(.clubs, [.ace])
                    + cards(.hearts, [.seven, .eight, .nine, .ten, .jack, .queen]),
                talon: cards(.hearts, [.king, .ace])
            )
        }
    }

    /// Engine deals in 5 packets of 2 cards per active seat with the talon
    /// landing in packet 0. Reverse-engineering the deck order from desired
    /// hands lets a test cover a specific scenario without scanning random
    /// shuffles.
    private func assemble(north: [Card], east: [Card], south: [Card], talon: [Card]) -> [Card] {
        DealDeckLayout.deck(
            hands: ["N": north, "E": east, "S": south],
            talon: talon,
            activePlayers: players
        )
    }

    private func makeSecondDefenderWhistEngine(secondDefenderHand south: [Card]) throws -> PreferansEngine {
        let north = [
            Card(.clubs, .ace),
            Card(.clubs, .king),
            Card(.clubs, .queen),
            Card(.clubs, .jack),
            Card(.clubs, .ten),
            Card(.clubs, .nine),
            Card(.hearts, .ace),
            Card(.hearts, .king),
            Card(.hearts, .queen),
            Card(.spades, .king)
        ].filter { !south.contains($0) }
        var declarerHand = north
        for card in Deck.standard32 where declarerHand.count < 10 && !south.contains(card) && !declarerHand.contains(card) {
            declarerHand.append(card)
        }
        let talon = [
            Card(.diamonds, .king),
            Card(.hearts, .ten)
        ].filter { !south.contains($0) && !declarerHand.contains($0) }
        var talonCards = talon
        for card in Deck.standard32 where talonCards.count < 2 && !south.contains(card) && !declarerHand.contains(card) && !talonCards.contains(card) {
            talonCards.append(card)
        }
        let reserved = Set(declarerHand + south + talonCards)
        let east = Deck.standard32.filter { !reserved.contains($0) }
        XCTAssertEqual(declarerHand.count, 10)
        XCTAssertEqual(south.count, 10)
        XCTAssertEqual(talonCards.count, 2)
        XCTAssertEqual(east.count, 10)

        var engine = try PreferansEngine(players: players, firstDealer: "S")
        _ = try engine.startDeal(deck: assemble(north: declarerHand, east: east, south: south, talon: talonCards))
        _ = try engine.apply(.bid(player: "N", call: .bid(.game(GameContract(6, .suit(.clubs))))))
        _ = try engine.apply(.bid(player: "E", call: .pass))
        _ = try engine.apply(.bid(player: "S", call: .pass))
        try EngineTestDriver.discardTalon(engine: &engine, declarer: "N")
        try EngineTestDriver.declareContract(engine: &engine, declarer: "N", contract: GameContract(6, .suit(.clubs)))
        _ = try engine.apply(.whist(player: "E", call: .whist))
        guard case let .awaitingWhist(whist) = engine.state else {
            throw EngineTestError("Expected awaitingWhist for second defender.")
        }
        XCTAssertEqual(whist.currentPlayer, "S")
        return engine
    }

    private func makeContractDeclarationEngine(
        hand north: [Card],
        finalBid: ContractBid
    ) throws -> PreferansEngine {
        XCTAssertEqual(north.count, 10)
        let remaining = Deck.standard32.filter { !north.contains($0) }
        let east = Array(remaining.prefix(10))
        let south = Array(remaining.dropFirst(10).prefix(10))
        let discard = Array(remaining.dropFirst(20).prefix(2))
        let talon = Array(north.prefix(2))
        let state = ContractDeclarationState(
            dealer: "S",
            activePlayers: players,
            hands: ["N": north, "E": east, "S": south],
            talon: talon,
            discard: discard,
            declarer: "N",
            finalBid: finalBid,
            auction: []
        )
        let snapshot = PreferansSnapshot(
            players: players,
            rules: .sochi,
            state: .awaitingContract(state),
            score: ScoreSheet(players: players),
            nextDealer: "E"
        )
        return try PreferansEngine(snapshot: snapshot)
    }
}
