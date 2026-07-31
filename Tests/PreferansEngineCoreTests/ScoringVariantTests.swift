import XCTest
@testable import PreferansEngine
@testable import PreferansEngineTestSupport

/// Pins the scoring behaviour of the ``PreferansRules`` knobs that move away
/// from the `.sochi` defaults: disabled failed-declarer consolation, disabled
/// whist responsibility, all-pass amnesty and multiplier variants, the
/// zero-trick all-pass pool bonus, and failed-misère mountain arithmetic.
final class ScoringVariantTests: XCTestCase {
    private let players: [PlayerID] = ["north", "east", "south"]

    // MARK: - failedDeclarerConsolation: .none

    func testFailedContractWithConsolationDisabledPaysNoDefenderConsolation() {
        let rules = PreferansRules(failedDeclarerConsolation: .none)
        let delta = scoreGame(
            contract: GameContract(7, .suit(.hearts)),
            whisters: ["east", "south"],
            trickCounts: ["north": 5, "east": 3, "south": 2],
            rules: rules
        )

        // Declarer still mountains the undertricks: value 4 * 2 = 8.
        XCTAssertEqual(delta.pool["north"], 0)
        XCTAssertEqual(delta.mountain["north"], 8)
        // Only the whisters' own tricks are written — no extra 4 * 2 = 8
        // consolation per defender (compare the .eachDefender test in
        // ScoringCalculationTests, where east gets 20 and south 16).
        XCTAssertEqual(delta.whists["east"]?["north"], 12) // 4 * 3 own tricks
        XCTAssertEqual(delta.whists["south"]?["north"], 8) // 4 * 2 own tricks
        // Both whisters met the 7-contract quota (2 / 2 whisters = 1 each),
        // so responsibility charges nothing either way.
        XCTAssertEqual(delta.mountain["east"], 0)
        XCTAssertEqual(delta.mountain["south"], 0)
    }

    // MARK: - whistResponsibility: .none

    func testWhistResponsibilityNoneChargesNoQuotaMountainToWhisters() {
        let rules = PreferansRules(whistResponsibility: .none)
        let delta = scoreGame(
            contract: GameContract(8, .suit(.spades)),
            whisters: ["east", "south"],
            trickCounts: ["north": 10, "east": 0, "south": 0],
            rules: rules
        )

        // Contract made: pool = value 6. Defenders missed the 1-trick quota
        // entirely, but the .none policy waives the 6-point mountain the
        // .responsible variant pins on the second whister.
        XCTAssertEqual(delta.pool["north"], 6)
        XCTAssertEqual(delta.mountain["east"], 0)
        XCTAssertEqual(delta.mountain["south"], 0)
        XCTAssertEqual(delta.whists["east"]?["north"], nil)
        XCTAssertEqual(delta.whists["south"]?["north"], nil)
    }

    func testWhistResponsibilityNoneLetsSingleWhisterMissQuotaFreely() {
        let rules = PreferansRules(whistResponsibility: .none)
        let delta = scoreGame(
            contract: GameContract(6, .suit(.diamonds)),
            whisters: ["east"],
            trickCounts: ["north": 7, "east": 1, "south": 2],
            rules: rules
        )

        // Greedy single whister still writes all defender tricks:
        // 2 * (1 + 2) = 6. The one-trick shortfall against the 4-trick
        // quota (defense took 3) costs nothing under .none — the
        // .responsible variant would mountain east 2.
        XCTAssertEqual(delta.pool["north"], 2)
        XCTAssertEqual(delta.whists["east"]?["north"], 6)
        XCTAssertEqual(delta.mountain["east"], 0)
    }

    // MARK: - All-pass penalty variants

    func testAllPassAmnestyChargesOnlyTricksAboveTableMinimum() {
        let rules = PreferansRules(allPassPenaltyPolicy: .perTrick(multiplier: 1, amnesty: true))
        let delta = scoreAllPass(
            trickCounts: ["north": 4, "east": 3, "south": 3],
            rules: rules
        )

        // Amnesty forgives everyone's share up to the table minimum (3):
        // north pays 4 - 3 = 1, east and south pay 3 - 3 = 0.
        XCTAssertEqual(delta.mountain["north"], 1)
        XCTAssertEqual(delta.mountain["east"], 0)
        XCTAssertEqual(delta.mountain["south"], 0)
        // Nobody exited clean, so no pool bonus is written.
        XCTAssertEqual(delta.pool, ["north": 0, "east": 0, "south": 0])
    }

    func testAllPassAmnestyWithZeroMinimumChargesFullTricksAndPaysCleanExitBonus() {
        let rules = PreferansRules(allPassPenaltyPolicy: .perTrick(multiplier: 1, amnesty: true))
        let delta = scoreAllPass(
            trickCounts: ["north": 0, "east": 5, "south": 5],
            rules: rules
        )

        // Minimum is 0, so amnesty forgives nothing: east and south each
        // mountain their full 5 tricks. North's clean exit earns the
        // default zero-trick pool bonus of 1 * multiplier 1 = 1.
        XCTAssertEqual(delta.pool["north"], 1)
        XCTAssertEqual(delta.mountain["north"], 0)
        XCTAssertEqual(delta.mountain["east"], 5)
        XCTAssertEqual(delta.mountain["south"], 5)
    }

    func testAllPassDoubledMultiplierDoublesMountainAndZeroTrickBonus() {
        let rules = PreferansRules(allPassPenaltyPolicy: .perTrick(multiplier: 2, amnesty: false))
        let delta = scoreAllPass(
            trickCounts: ["north": 0, "east": 6, "south": 4],
            rules: rules
        )

        // Every trick costs 2: east mountains 6 * 2 = 12, south 4 * 2 = 8.
        // The clean exit bonus is also multiplied: 1 * 2 = 2 pool.
        XCTAssertEqual(delta.pool["north"], 2)
        XCTAssertEqual(delta.mountain["north"], 0)
        XCTAssertEqual(delta.mountain["east"], 12)
        XCTAssertEqual(delta.mountain["south"], 8)
    }

    func testZeroTricksAllPassPoolBonusZeroGrantsNoCleanExitPool() {
        let rules = PreferansRules(zeroTricksAllPassPoolBonus: 0)
        let delta = scoreAllPass(
            trickCounts: ["north": 0, "east": 6, "south": 4],
            rules: rules
        )

        // The clean exit still costs nothing, but earns nothing either.
        XCTAssertEqual(delta.pool, ["north": 0, "east": 0, "south": 0])
        XCTAssertEqual(delta.mountain["north"], 0)
        XCTAssertEqual(delta.mountain["east"], 6)
        XCTAssertEqual(delta.mountain["south"], 4)
    }

    func testCanonicalSochiRaspasyUsesTalonLeadAndAmnesty() {
        XCTAssertEqual(PreferansRules.sochi.allPassTalonPolicy, .classic)
        XCTAssertEqual(PreferansRules.sochi.dealerTalonCompensation, .classic)
        XCTAssertEqual(PreferansRules.leningrad.dealerTalonCompensation, .classic)
        guard case let .perTrick(multiplier, amnesty) = PreferansRules.sochi.allPassPenaltyPolicy else {
            return XCTFail("Expected per-trick Sochi raspasy scoring.")
        }
        XCTAssertEqual(multiplier, 1)
        XCTAssertTrue(amnesty)

        let delta = scoreAllPass(
            trickCounts: ["north": 4, "east": 3, "south": 3],
            rules: .sochi
        )
        XCTAssertEqual(delta.mountain, ["north": 1, "east": 0, "south": 0])
    }

    func testSochiRaspasyPriceProgressesOneTwoThreeAndCaps() {
        let match = MatchSettings(raspasy: .sochi)
        for (precedingDeals, price) in [1, 2, 3, 3].enumerated() {
            let delta = scoreAllPass(
                trickCounts: ["north": 0, "east": 4, "south": 6],
                rules: .sochi,
                match: match,
                consecutiveAllPassDeals: precedingDeals
            )
            XCTAssertEqual(delta.pool["north"], price)
            XCTAssertEqual(delta.mountain["east"], 4 * price)
            XCTAssertEqual(delta.mountain["south"], 6 * price)
        }
    }

    func testLeningradRaspasyUsesDoubledTwoFourSixSeries() {
        let delta = scoreAllPass(
            trickCounts: ["north": 0, "east": 4, "south": 6],
            rules: .leningrad,
            match: MatchSettings(raspasy: .leningrad),
            consecutiveAllPassDeals: 2
        )

        // Leningrad's base price is 2 and the third arithmetic stage is x3.
        XCTAssertEqual(delta.pool["north"], 6)
        XCTAssertEqual(delta.mountain["east"], 24)
        XCTAssertEqual(delta.mountain["south"], 36)
    }

    func testExecutableRulebookUsesTheProductionScorer() {
        let sochi = PreferansRulebook.examples(
            rules: .sochi,
            match: MatchSettings(raspasy: .sochi)
        )
        XCTAssertEqual(sochi.contracts.map(\.madePool), [2, 4, 6, 8, 10])
        XCTAssertEqual(sochi.contracts.map(\.failedByOneMountain), [2, 4, 6, 8, 10])
        XCTAssertEqual(sochi.contracts.map(\.whistPerDefenderTrick), [2, 4, 6, 8, 10])
        XCTAssertEqual(sochi.misere, MisereRuleExample(madePool: 10, failedOneTrickMountain: 10))
        XCTAssertEqual(sochi.raspasy.map(\.trickPrice), [1, 2, 3])
        XCTAssertEqual(sochi.raspasy.map(\.cleanExitPool), [1, 2, 3])
        XCTAssertEqual(sochi.raspasy.map(\.minimumGameTricks), [6, 7, 8])
        XCTAssertEqual(sochi.raspasy.map(\.mountainForZeroFourSix), [
            [0, 4, 6], [0, 8, 12], [0, 12, 18],
        ])

        let leningrad = PreferansRulebook.examples(
            rules: .leningrad,
            match: MatchSettings(poolClosure: .tableTotal, raspasy: .leningrad)
        )
        XCTAssertEqual(leningrad.contracts.map(\.madePool), [2, 4, 6, 8, 10])
        XCTAssertEqual(leningrad.contracts.map(\.failedByOneMountain), [4, 8, 12, 16, 20])
        XCTAssertEqual(leningrad.contracts.map(\.whistPerDefenderTrick), [4, 8, 12, 16, 20])
        XCTAssertEqual(leningrad.misere, MisereRuleExample(madePool: 10, failedOneTrickMountain: 20))
        XCTAssertEqual(leningrad.raspasy.map(\.trickPrice), [2, 4, 6])
        XCTAssertEqual(leningrad.raspasy.map(\.cleanExitPool), [2, 4, 6])
        XCTAssertEqual(leningrad.raspasy.map(\.minimumGameTricks), [6, 7, 8])
    }

    // MARK: - Leningrad recording scale

    func testLeningradKeepsPoolBaseValueAndDoublesMountainAndWhists() {
        let made = scoreGame(
            contract: GameContract(6, .suit(.clubs)),
            whisters: ["east", "south"],
            trickCounts: ["north": 6, "east": 1, "south": 3],
            rules: .leningrad
        )
        XCTAssertEqual(made.pool["north"], 2)
        XCTAssertEqual(made.whists["east"]?["north"], 4)
        XCTAssertEqual(made.whists["south"]?["north"], 12)

        let failed = scoreGame(
            contract: GameContract(6, .suit(.clubs)),
            whisters: ["east", "south"],
            trickCounts: ["north": 5, "east": 3, "south": 2],
            rules: .leningrad
        )
        XCTAssertEqual(failed.mountain["north"], 4)
        XCTAssertEqual(failed.whists["east"]?["north"], 16)
        XCTAssertEqual(failed.whists["south"]?["north"], 12)
    }

    func testLeningradMisereKeepsTenPoolButDoublesRemise() {
        let made = scoreMisere(
            trickCounts: ["north": 0, "east": 5, "south": 5],
            rules: .leningrad
        )
        XCTAssertEqual(made.pool["north"], 10)

        let failed = scoreMisere(
            trickCounts: ["north": 1, "east": 5, "south": 4],
            rules: .leningrad
        )
        XCTAssertEqual(failed.mountain["north"], 20)
    }

    // MARK: - Four-player dealer talon compensation

    func testClassicDealerTalonCombinationsWriteContractWhists() {
        let contract = GameContract(6, .suit(.clubs))
        let cases: [(name: String, talon: [Card], expected: Int)] = [
            ("two aces count as three tricks", [Card(.spades, .ace), Card(.hearts, .ace)], 6),
            ("suited ace king counts as two", [Card(.spades, .ace), Card(.spades, .king)], 4),
            ("one ace counts as one", [Card(.spades, .ace), Card(.hearts, .nine)], 2),
            ("suited marriage counts as one", [Card(.clubs, .king), Card(.clubs, .queen)], 2),
            ("ordinary talon pays nothing", [Card(.clubs, .nine), Card(.hearts, .ten)], 0),
        ]

        for example in cases {
            let delta = scoreFourPlayerGame(
                contract: contract,
                talon: example.talon,
                rules: .sochi
            )
            XCTAssertEqual(
                delta.whists["west"]?["north"] ?? 0,
                example.expected,
                example.name
            )
        }
    }

    func testDealerTalonCompensationCanBeDisabled() {
        let rules = PreferansRules(dealerTalonCompensation: .none)
        let delta = scoreFourPlayerGame(
            contract: GameContract(6, .suit(.clubs)),
            talon: [Card(.spades, .ace), Card(.hearts, .ace)],
            rules: rules
        )

        XCTAssertEqual(delta.whists["west"]?["north"] ?? 0, 0)
    }

    func testMisereDealerTalonCompensationUsesTheVariantWhistScale() {
        let suitedSevenEight = [Card(.diamonds, .seven), Card(.diamonds, .eight)]
        let twoSevens = [Card(.spades, .seven), Card(.hearts, .seven)]

        XCTAssertEqual(
            scoreFourPlayerMisere(talon: suitedSevenEight, rules: .sochi)
                .whists["west"]?["north"],
            20
        )
        XCTAssertEqual(
            scoreFourPlayerMisere(talon: twoSevens, rules: .sochi)
                .whists["west"]?["north"],
            20
        )
        XCTAssertEqual(
            scoreFourPlayerMisere(talon: suitedSevenEight, rules: .leningrad)
                .whists["west"]?["north"],
            40
        )
    }

    func testDealerTalonCompensationSurvivesPassOutAndHalfWhist() {
        let talon = [Card(.spades, .ace), Card(.hearts, .ace)]
        let whist = fourPlayerWhistState(talon: talon)
        let scoring = PreferansScoring(
            players: fourPlayers,
            rules: .sochi,
            match: .unbounded
        )

        let passedOut = scoring.passedOut(whist).scoreDelta
        let halfWhist = scoring.halfWhist(whist, halfWhister: "east").scoreDelta

        XCTAssertEqual(passedOut.whists["west"]?["north"], 6)
        XCTAssertEqual(halfWhist.whists["west"]?["north"], 6)
    }

    func testFourPlayerRaspasyDealerParticipatesInAmnestyAndCleanExit() {
        let cleanDealer = scoreFourPlayerAllPass(
            trickCounts: ["north": 4, "east": 3, "south": 3, "west": 0]
        )
        XCTAssertEqual(cleanDealer.pool["west"], 1)
        XCTAssertEqual(cleanDealer.mountain, ["north": 4, "east": 3, "south": 3, "west": 0])

        let oneDealerTrick = scoreFourPlayerAllPass(
            trickCounts: ["north": 3, "east": 3, "south": 3, "west": 1]
        )
        XCTAssertEqual(oneDealerTrick.pool["west"], 0)
        XCTAssertEqual(oneDealerTrick.mountain, ["north": 2, "east": 2, "south": 2, "west": 0])
    }

    // MARK: - Failed misère

    func testFailedMisereChargesTenMountainPerDeclarerTrick() {
        let delta = scoreMisere(trickCounts: ["north": 3, "east": 4, "south": 3])

        // Any declarer trick fails the misère: mountain = 10 * 3 = 30,
        // no pool, and defenders write nothing.
        XCTAssertEqual(delta.pool["north"], 0)
        XCTAssertEqual(delta.mountain["north"], 30)
        XCTAssertEqual(delta.mountain["east"], 0)
        XCTAssertEqual(delta.mountain["south"], 0)
        XCTAssertEqual(delta.whists["east"]?["north"], nil)
        XCTAssertEqual(delta.whists["south"]?["north"], nil)
    }

    func testMisereDeclarerForcedToTakeEveryTrickMountainsOneHundred() throws {
        var engine = try PreferansEngine(players: players, firstDealer: "south")
        try engine.startDeal(deck: Self.trappedMisereDeck)

        // Rotation for dealer south is [north, east, south]; north opens.
        _ = try engine.apply(.bid(player: "north", call: .bid(.misere)))
        _ = try engine.apply(.bid(player: "east", call: .pass))
        _ = try engine.apply(.bid(player: "south", call: .pass))
        try EngineTestDriver.discardTalon(engine: &engine, declarer: "north")
        try EngineTestDriver.playOut(engine: &engine, policy: .lowestLegal)

        guard case let .dealFinished(result) = engine.state,
              case let .misere(declarer) = result.kind else {
            return XCTFail("Expected dealFinished.misere; got \(engine.state.description).")
        }
        XCTAssertEqual(declarer, "north")
        // North holds only winners (every card outranks both defenders in
        // its suit) and leads the first trick, so lowest-legal play forces
        // all ten tricks onto the declarer.
        XCTAssertEqual(result.trickCounts, ["north": 10, "east": 0, "south": 0])
        // Failed misère mountains 10 per declarer trick: 10 * 10 = 100.
        XCTAssertEqual(engine.score.mountain["north"], 100)
        XCTAssertEqual(engine.score.pool["north"], 0)
        XCTAssertEqual(engine.score.whistsWritten(by: "east", on: "north"), 0)
        XCTAssertEqual(engine.score.whistsWritten(by: "south", on: "north"), 0)
    }

    // MARK: - Helpers

    private func scoreGame(
        contract: GameContract,
        whisters: [PlayerID],
        trickCounts: [PlayerID: Int],
        rules: PreferansRules,
        match: MatchSettings = .unbounded
    ) -> ScoreDelta {
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
        return score(kind: .game(context), trickCounts: trickCounts, rules: rules, match: match)
    }

    private var fourPlayers: [PlayerID] { ["north", "east", "south", "west"] }

    private func scoreFourPlayerGame(
        contract: GameContract,
        talon: [Card],
        rules: PreferansRules
    ) -> ScoreDelta {
        let active: [PlayerID] = ["north", "east", "south"]
        let defenders: [PlayerID] = ["east", "south"]
        let context = GamePlayContext(
            declarer: "north",
            contract: contract,
            defenders: defenders,
            whisters: defenders,
            defenderPlayMode: .closed,
            whistCalls: defenders.map { WhistCallRecord(player: $0, call: .whist) }
        )
        let playing = PlayingState(
            dealer: "west",
            activePlayers: active,
            hands: active.dictionary(filledWith: []),
            talon: talon,
            leader: "north",
            currentPlayer: "north",
            trickCounts: ["north": 6, "east": 2, "south": 2],
            kind: .game(context)
        )
        return PreferansScoring(players: fourPlayers, rules: rules, match: .unbounded)
            .completedPlay(playing).scoreDelta
    }

    private func scoreFourPlayerMisere(
        talon: [Card],
        rules: PreferansRules
    ) -> ScoreDelta {
        let active: [PlayerID] = ["north", "east", "south"]
        let playing = PlayingState(
            dealer: "west",
            activePlayers: active,
            hands: active.dictionary(filledWith: []),
            talon: talon,
            leader: "north",
            currentPlayer: "north",
            trickCounts: ["north": 0, "east": 5, "south": 5],
            kind: .misere(MiserePlayContext(declarer: "north"))
        )
        return PreferansScoring(players: fourPlayers, rules: rules, match: .unbounded)
            .completedPlay(playing).scoreDelta
    }

    private func fourPlayerWhistState(talon: [Card]) -> WhistState {
        let active: [PlayerID] = ["north", "east", "south"]
        return WhistState(
            dealer: "west",
            activePlayers: active,
            hands: active.dictionary(filledWith: []),
            talon: talon,
            discard: [],
            declarer: "north",
            contract: GameContract(6, .suit(.clubs)),
            defenders: ["east", "south"],
            currentPlayer: "east"
        )
    }

    private func scoreFourPlayerAllPass(trickCounts: [PlayerID: Int]) -> ScoreDelta {
        let active: [PlayerID] = ["north", "east", "south"]
        let playing = PlayingState(
            dealer: "west",
            activePlayers: active,
            hands: active.dictionary(filledWith: []),
            talon: [Card(.spades, .ace), Card(.hearts, .seven)],
            leader: "north",
            currentPlayer: "north",
            trickCounts: trickCounts,
            kind: .allPass(AllPassPlayContext(talonPolicy: .classic))
        )
        return PreferansScoring(players: fourPlayers, rules: .sochi, match: .unbounded)
            .completedPlay(playing).scoreDelta
    }

    private func scoreAllPass(
        trickCounts: [PlayerID: Int],
        rules: PreferansRules,
        match: MatchSettings = .unbounded,
        consecutiveAllPassDeals: Int = 0
    ) -> ScoreDelta {
        score(
            kind: .allPass(AllPassPlayContext(talonPolicy: rules.allPassTalonPolicy)),
            trickCounts: trickCounts,
            rules: rules,
            match: match,
            consecutiveAllPassDeals: consecutiveAllPassDeals
        )
    }

    private func scoreMisere(
        trickCounts: [PlayerID: Int],
        rules: PreferansRules = .sochi,
        match: MatchSettings = .unbounded
    ) -> ScoreDelta {
        score(
            kind: .misere(MiserePlayContext(declarer: "north")),
            trickCounts: trickCounts,
            rules: rules,
            match: match
        )
    }

    private func score(
        kind: PlayKind,
        trickCounts: [PlayerID: Int],
        rules: PreferansRules,
        match: MatchSettings,
        consecutiveAllPassDeals: Int = 0
    ) -> ScoreDelta {
        let scoring = PreferansScoring(
            players: players,
            rules: rules,
            match: match,
            consecutiveAllPassDeals: consecutiveAllPassDeals
        )
        let playing = PlayingState(
            dealer: "south",
            activePlayers: players,
            hands: Dictionary(uniqueKeysWithValues: players.map { ($0, [Card]()) }),
            talon: [],
            leader: "north",
            currentPlayer: "north",
            trickCounts: trickCounts,
            kind: kind
        )
        return scoring.completedPlay(playing).scoreDelta
    }

    /// North's post-discard hand is the ten highest cards of every suit it
    /// holds — each card outranks both defenders' best in its suit — and
    /// north leads the first trick, so a misère here cannot avoid taking
    /// all ten tricks under lowest-legal play.
    private static let trappedMisereDeck: [Card] = {
        let north: [Card] = [
            Card(.spades, .ace), Card(.spades, .king), Card(.spades, .queen),
            Card(.clubs, .ace), Card(.clubs, .king), Card(.clubs, .queen),
            Card(.diamonds, .ace), Card(.diamonds, .king),
            Card(.hearts, .ace), Card(.hearts, .king)
        ]
        let east: [Card] = [
            Card(.spades, .jack), Card(.spades, .ten), Card(.spades, .nine),
            Card(.clubs, .jack), Card(.clubs, .ten), Card(.clubs, .nine),
            Card(.clubs, .eight), Card(.clubs, .seven),
            Card(.diamonds, .eight), Card(.diamonds, .seven)
        ]
        let south: [Card] = [
            Card(.diamonds, .queen), Card(.diamonds, .jack),
            Card(.diamonds, .ten), Card(.diamonds, .nine),
            Card(.hearts, .queen), Card(.hearts, .jack), Card(.hearts, .ten),
            Card(.hearts, .nine), Card(.hearts, .eight), Card(.hearts, .seven)
        ]
        let talon: [Card] = [Card(.spades, .seven), Card(.spades, .eight)]
        return DealDeckLayout.deck(north: north, east: east, south: south, talon: talon)
    }()
}
