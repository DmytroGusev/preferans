import XCTest
@testable import PreferansEngine
@testable import PreferansEngineTestSupport

/// Negative tests for ``PreferansEngine/validateInvariants(_:)``. Each test
/// constructs a ``DealState`` with exactly one invariant violated and asserts
/// the validator throws an ``InvariantViolation`` whose message names the
/// violated rule. Positive paths are already covered by the engine's
/// happy-path tests — this file proves the invariants actually fire.
final class InvariantValidatorTests: XCTestCase {

    // MARK: - Fixtures

    private let north: PlayerID = "north"
    private let east: PlayerID = "east"
    private let south: PlayerID = "south"

    private var seats: [PlayerID] { [north, east, south] }

    /// 10/10/10 hand split + 2-card talon, drawn from the standard deck so
    /// every card is unique and accounted for.
    private func dealHands() -> (hands: [PlayerID: [Card]], talon: [Card]) {
        let deck = Deck.standard32
        let hands: [PlayerID: [Card]] = [
            north: Array(deck[0..<10]),
            east:  Array(deck[10..<20]),
            south: Array(deck[20..<30]),
        ]
        let talon = Array(deck[30..<32])
        return (hands, talon)
    }

    private func biddingFixture(
        seats overrideSeats: [PlayerID]? = nil,
        hands overrideHands: [PlayerID: [Card]]? = nil,
        talon overrideTalon: [Card]? = nil,
        currentPlayer overrideCurrent: PlayerID? = nil,
        passed: Set<PlayerID> = [],
        highestBid: ContractBid? = nil,
        highestBidder: PlayerID? = nil,
        calls: [AuctionCall] = [],
        significantBidByPlayer: [PlayerID: ContractBid] = [:]
    ) -> BiddingState {
        let (hands, talon) = dealHands()
        let activeSeats = overrideSeats ?? seats
        return BiddingState(
            dealer: north,
            activePlayers: activeSeats,
            hands: overrideHands ?? hands,
            talon: overrideTalon ?? talon,
            currentPlayer: overrideCurrent ?? activeSeats[0],
            passed: passed,
            highestBid: highestBid,
            highestBidder: highestBidder,
            calls: calls,
            significantBidByPlayer: significantBidByPlayer
        )
    }

    private func playingFixture(
        seats overrideSeats: [PlayerID]? = nil,
        hands overrideHands: [PlayerID: [Card]]? = nil,
        leader overrideLeader: PlayerID? = nil,
        currentPlayer overrideCurrent: PlayerID? = nil,
        completedTricks: [Trick] = [],
        currentTrick: [CardPlay] = [],
        trickCounts overrideCounts: [PlayerID: Int]? = nil
    ) -> PlayingState {
        let (hands, talon) = dealHands()
        let activeSeats = overrideSeats ?? seats
        let kind = PlayKind.allPass(AllPassPlayContext(talonPolicy: .leadSuitOnly))
        return PlayingState(
            dealer: north,
            activePlayers: activeSeats,
            hands: overrideHands ?? hands,
            talon: talon,
            discard: [],
            leader: overrideLeader ?? activeSeats[0],
            currentPlayer: overrideCurrent ?? activeSeats[0],
            currentTrick: currentTrick,
            completedTricks: completedTricks,
            trickCounts: overrideCounts,
            kind: kind
        )
    }

    private func whistFixture(
        defenders: [PlayerID] = ["east", "south"],
        currentPlayer: PlayerID = "east",
        calls: [WhistCallRecord] = [],
        flow: WhistState.HalfWhistFlow = .normal,
        bonusPoolOnSuccess: Int = 0
    ) -> WhistState {
        let (hands, talon) = dealHands()
        return WhistState(
            dealer: south,
            activePlayers: seats,
            hands: hands,
            talon: talon,
            discard: talon,
            declarer: north,
            contract: GameContract(6, .suit(.spades)),
            defenders: defenders,
            currentPlayer: currentPlayer,
            calls: calls,
            flow: flow,
            bonusPoolOnSuccess: bonusPoolOnSuccess
        )
    }

    private func defenderModeFixture(
        defenders: [PlayerID] = ["east", "south"],
        whister: PlayerID = "east",
        whistCalls: [WhistCallRecord] = [
            WhistCallRecord(player: "east", call: .whist),
            WhistCallRecord(player: "south", call: .pass),
        ],
        bonusPoolOnSuccess: Int = 0
    ) -> DefenderModeState {
        let (hands, talon) = dealHands()
        return DefenderModeState(
            dealer: south,
            activePlayers: seats,
            hands: hands,
            talon: talon,
            discard: talon,
            declarer: north,
            contract: GameContract(6, .suit(.spades)),
            defenders: defenders,
            whister: whister,
            whistCalls: whistCalls,
            bonusPoolOnSuccess: bonusPoolOnSuccess
        )
    }

    private func assertViolation(
        _ state: DealState,
        contains needle: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            try PreferansEngine.validateInvariants(state)
            XCTFail("expected invariant violation containing '\(needle)' but validator accepted state", file: file, line: line)
        } catch let violation as InvariantViolation {
            XCTAssertTrue(
                violation.message.contains(needle),
                "violation '\(violation.message)' did not contain '\(needle)'",
                file: file, line: line
            )
        } catch {
            XCTFail("expected InvariantViolation, got \(error)", file: file, line: line)
        }
    }

    private func assertViolation(
        _ snapshot: PreferansSnapshot,
        contains needle: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            try PreferansEngine.validateInvariants(snapshot)
            XCTFail("expected invariant violation containing '\(needle)' but validator accepted snapshot", file: file, line: line)
        } catch let violation as InvariantViolation {
            XCTAssertTrue(
                violation.message.contains(needle),
                "violation '\(violation.message)' did not contain '\(needle)'",
                file: file,
                line: line
            )
        } catch {
            XCTFail("expected InvariantViolation, got \(error)", file: file, line: line)
        }
    }

    private func assertViolation(
        _ operation: @autoclosure () throws -> Void,
        contains needle: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        do {
            try operation()
            XCTFail("expected invariant violation containing '\(needle)' but operation succeeded", file: file, line: line)
        } catch let violation as InvariantViolation {
            XCTAssertTrue(
                violation.message.contains(needle),
                "violation '\(violation.message)' did not contain '\(needle)'",
                file: file,
                line: line
            )
        } catch {
            XCTFail("expected InvariantViolation, got \(error)", file: file, line: line)
        }
    }

    private func assertAccepts(_ state: DealState, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNoThrow(try PreferansEngine.validateInvariants(state), file: file, line: line)
    }

    // MARK: - Positive controls

    func testValidatorAcceptsHappyPathBidding() {
        assertAccepts(.bidding(biddingFixture()))
    }

    func testValidatorAcceptsHappyPathPlaying() {
        assertAccepts(.playing(playingFixture()))
    }

    func testValidatorAcceptsTerminalStates() {
        assertAccepts(.waitingForDeal)
    }

    // MARK: - Active-seat invariants

    func testValidatorRejectsBiddingWithFourActiveSeats() {
        let extraSeat: PlayerID = "west"
        var (hands, talon) = dealHands()
        hands[extraSeat] = Array(repeating: Card(.hearts, .seven), count: 10)
        let state = DealState.bidding(biddingFixture(
            seats: [north, east, south, extraSeat],
            hands: hands,
            talon: talon
        ))
        assertViolation(state, contains: "active seats must be 3")
    }

    func testValidatorRejectsBiddingWithDuplicateActiveSeat() {
        let (hands, talon) = dealHands()
        // hands keyed by 3 unique players; activePlayers has a duplicate
        let state = DealState.bidding(BiddingState(
            dealer: north,
            activePlayers: [north, east, north],
            hands: hands,
            talon: talon,
            currentPlayer: north
        ))
        assertViolation(state, contains: "duplicate seat")
    }

    // MARK: - Hand invariants

    func testValidatorRejectsBiddingWithMissingHandKey() {
        var (hands, talon) = dealHands()
        hands.removeValue(forKey: south)
        // Replace south's cards as east's so the dictionary has only 2 keys
        let state = DealState.bidding(biddingFixture(hands: hands, talon: talon))
        assertViolation(state, contains: "hand keys")
    }

    func testValidatorRejectsBiddingWithWrongHandSize() {
        var (hands, talon) = dealHands()
        hands[north] = Array(hands[north]!.dropLast()) // 9 cards
        let state = DealState.bidding(biddingFixture(hands: hands, talon: talon))
        assertViolation(state, contains: "expected 10")
    }

    func testValidatorRejectsBiddingWithDuplicateCardsInHand() {
        var (hands, talon) = dealHands()
        // Replace north's last card with a duplicate of the first
        var northHand = hands[north]!
        northHand[northHand.count - 1] = northHand[0]
        hands[north] = northHand
        let state = DealState.bidding(biddingFixture(hands: hands, talon: talon))
        assertViolation(state, contains: "duplicate cards")
    }

    // MARK: - Talon / discard size

    func testValidatorRejectsBiddingWithBadTalonSize() {
        let (hands, _) = dealHands()
        let state = DealState.bidding(biddingFixture(hands: hands, talon: [Card(.spades, .seven)]))
        assertViolation(state, contains: "talon must be 2 cards")
    }

    func testValidatorRejectsAwaitingContractWithBadDiscardSize() {
        let (hands, talon) = dealHands()
        let bid = ContractBid.game(GameContract(6, .suit(.spades)))
        let state = DealState.awaitingContract(ContractDeclarationState(
            dealer: north,
            activePlayers: seats,
            hands: hands,
            talon: talon,
            discard: [Card(.spades, .seven)], // only 1 card
            declarer: north,
            finalBid: bid,
            auction: []
        ))
        assertViolation(state, contains: "discard must be 2 cards")
    }

    // MARK: - Membership invariants

    func testValidatorRejectsBiddingWithCurrentPlayerNotInActivePlayers() {
        let stranger: PlayerID = "ghost"
        let state = DealState.bidding(biddingFixture(currentPlayer: stranger))
        assertViolation(state, contains: "currentPlayer")
    }

    func testValidatorRejectsBiddingWithPassedNotSubsetOfActivePlayers() {
        let stranger: PlayerID = "ghost"
        let state = DealState.bidding(biddingFixture(passed: [stranger]))
        assertViolation(state, contains: "passed")
    }

    func testValidatorRejectsBiddingWhenCurrentPlayerAlreadyPassed() {
        let state = DealState.bidding(biddingFixture(
            passed: [north],
            calls: [AuctionCall(player: north, call: .pass)]
        ))

        assertViolation(state, contains: "currentPlayer cannot already have passed")
    }

    func testValidatorRejectsBiddingWhenSignificantBidLedgerForgetsARealBid() {
        let sixSpades = ContractBid.game(GameContract(6, .suit(.spades)))
        let state = DealState.bidding(biddingFixture(
            currentPlayer: east,
            highestBid: sixSpades,
            highestBidder: north,
            calls: [AuctionCall(player: north, call: .bid(sixSpades))],
            significantBidByPlayer: [:]
        ))

        assertViolation(state, contains: "significant bid ledger")
    }

    func testSnapshotRehydrationRejectsAuctionLedgerThatWouldReopenMisere() {
        let sixSpades = ContractBid.game(GameContract(6, .suit(.spades)))
        let state = DealState.bidding(biddingFixture(
            currentPlayer: east,
            highestBid: sixSpades,
            highestBidder: north,
            calls: [AuctionCall(player: north, call: .bid(sixSpades))],
            significantBidByPlayer: [:]
        ))
        let snapshot = PreferansSnapshot(
            players: seats,
            rules: .sochi,
            state: state,
            score: ScoreSheet(players: seats),
            nextDealer: east
        )

        assertViolation(
            try { _ = try PreferansEngine(snapshot: snapshot) }(),
            contains: "significant bid ledger"
        )
    }

    func testValidatorRejectsBiddingWhenPassedSetDisagreesWithCalls() {
        let state = DealState.bidding(biddingFixture(
            currentPlayer: east,
            calls: [AuctionCall(player: north, call: .pass)]
        ))

        assertViolation(state, contains: "passed set does not match auction calls")
    }

    func testValidatorRejectsBiddingWhenHighestBidDisagreesWithLastBid() {
        let sixSpades = ContractBid.game(GameContract(6, .suit(.spades)))
        let sixClubs = ContractBid.game(GameContract(6, .suit(.clubs)))
        let state = DealState.bidding(biddingFixture(
            currentPlayer: south,
            highestBid: sixSpades,
            highestBidder: north,
            calls: [
                AuctionCall(player: north, call: .bid(sixSpades)),
                AuctionCall(player: east, call: .bid(sixClubs)),
            ],
            significantBidByPlayer: [north: sixSpades, east: sixClubs]
        ))

        assertViolation(state, contains: "highest bid must match the last auction bid")
    }

    func testValidatorRejectsAwaitingWhistWithDeclarerInDefenders() {
        let (hands, talon) = dealHands()
        let contract = GameContract(6, .suit(.spades))
        let state = DealState.awaitingWhist(WhistState(
            dealer: north,
            activePlayers: seats,
            hands: hands,
            talon: talon,
            discard: Array(talon),
            declarer: north,
            contract: contract,
            defenders: [north, south], // declarer wrongly listed as a defender
            currentPlayer: south
        ))
        assertViolation(state, contains: "declarer")
    }

    func testValidatorRejectsAwaitingWhistSnapshotWithSingleDefender() {
        // The whist reducer indexes defenders[0] and defenders[1] without
        // checking the count, so a corrupted snapshot carrying a lone
        // defender must fail validation at rehydration instead of crashing
        // on the first whist call.
        let (hands, talon) = dealHands()
        let contract = GameContract(6, .suit(.spades))
        let state = DealState.awaitingWhist(WhistState(
            dealer: north,
            activePlayers: seats,
            hands: hands,
            talon: talon,
            discard: Array(talon),
            declarer: north,
            contract: contract,
            defenders: [east], // corrupted: south is missing
            currentPlayer: east
        ))
        let snapshot = PreferansSnapshot(
            players: seats,
            rules: .sochi,
            state: state,
            score: ScoreSheet(players: seats),
            nextDealer: east
        )
        assertViolation(snapshot, contains: "defenders must be 2")
    }

    func testValidatorRejectsAwaitingDefenderModeWithSingleDefender() {
        let (hands, talon) = dealHands()
        let contract = GameContract(6, .suit(.spades))
        let state = DealState.awaitingDefenderMode(DefenderModeState(
            dealer: north,
            activePlayers: seats,
            hands: hands,
            talon: talon,
            discard: Array(talon),
            declarer: north,
            contract: contract,
            defenders: [east], // corrupted: south is missing
            whister: east,
            whistCalls: [],
            bonusPoolOnSuccess: 0
        ))
        assertViolation(state, contains: "defenders must be 2")
    }

    func testValidatorRejectsAwaitingWhistWithDuplicateDefenders() {
        let state = DealState.awaitingWhist(whistFixture(defenders: [east, east]))

        assertViolation(state, contains: "ordered active seats excluding declarer")
    }

    func testValidatorRejectsAwaitingWhistWithDefendersOutOfTurnOrder() {
        let state = DealState.awaitingWhist(whistFixture(
            defenders: [south, east],
            currentPlayer: south
        ))

        assertViolation(state, contains: "ordered active seats excluding declarer")
    }

    func testValidatorRejectsAwaitingWhistWhenDeclarerIsCurrentPlayer() {
        let state = DealState.awaitingWhist(whistFixture(currentPlayer: north))

        assertViolation(state, contains: "currentPlayer must be a defender")
    }

    func testValidatorRejectsAwaitingWhistCallFromSecondDefenderFirst() {
        let state = DealState.awaitingWhist(whistFixture(
            currentPlayer: south,
            calls: [WhistCallRecord(player: south, call: .pass)]
        ))

        assertViolation(state, contains: "first call must come from first defender")
    }

    func testValidatorRejectsForgedHalfWhistSecondChanceOwner() {
        let state = DealState.awaitingWhist(whistFixture(
            currentPlayer: east,
            calls: [
                WhistCallRecord(player: east, call: .pass),
                WhistCallRecord(player: south, call: .halfWhist),
            ],
            flow: .firstDefenderSecondChance(halfWhister: east)
        ))

        assertViolation(state, contains: "half-whister must be second defender")
    }

    func testValidatorRejectsDefenderModeWhisterOutsideDefendingSide() {
        let state = DealState.awaitingDefenderMode(defenderModeFixture(whister: north))

        assertViolation(state, contains: "whister must be a defender")
    }

    func testValidatorRejectsDefenderModeWithoutExactlyOneWhister() {
        let state = DealState.awaitingDefenderMode(defenderModeFixture(
            whistCalls: [
                WhistCallRecord(player: east, call: .whist),
                WhistCallRecord(player: south, call: .whist),
            ]
        ))

        assertViolation(state, contains: "exactly one whist and one pass")
    }

    func testValidatorRejectsNegativeTotusBonusInWhistPhase() {
        let state = DealState.awaitingWhist(whistFixture(bonusPoolOnSuccess: -1))

        assertViolation(state, contains: "bonusPoolOnSuccess cannot be negative")
    }

    // MARK: - Playing-state invariants

    func testValidatorRejectsPlayingWithMismatchedTrickCountsKeys() {
        let badCounts: [PlayerID: Int] = [north: 0, east: 0] // missing south
        let state = DealState.playing(playingFixture(trickCounts: badCounts))
        assertViolation(state, contains: "trickCounts keys")
    }

    func testValidatorRejectsPlayingWithLeaderNotInActivePlayers() {
        let stranger: PlayerID = "ghost"
        let state = DealState.playing(playingFixture(leader: stranger))
        assertViolation(state, contains: "leader")
    }

    func testValidatorRejectsPlayingWithDeclarerInDefenders() {
        let (hands, talon) = dealHands()
        let contract = GameContract(6, .suit(.spades))
        let state = DealState.playing(PlayingState(
            dealer: north,
            activePlayers: seats,
            hands: hands,
            talon: talon,
            discard: Array(talon),
            leader: north,
            currentPlayer: north,
            kind: .game(GamePlayContext(
                declarer: north,
                contract: contract,
                defenders: [north, south],
                whisters: [],
                defenderPlayMode: .closed,
                whistCalls: []
            ))
        ))
        assertViolation(state, contains: "declarer")
    }

    func testValidatorRejectsPlayingWithWhistersOutsideDefenders() {
        let (hands, talon) = dealHands()
        let contract = GameContract(6, .suit(.spades))
        let state = DealState.playing(PlayingState(
            dealer: north,
            activePlayers: seats,
            hands: hands,
            talon: talon,
            discard: Array(talon),
            leader: north,
            currentPlayer: north,
            kind: .game(GamePlayContext(
                declarer: north,
                contract: contract,
                defenders: [east, south],
                whisters: ["ghost"],
                defenderPlayMode: .closed,
                whistCalls: []
            ))
        ))
        assertViolation(state, contains: "whisters")
    }

    func testValidatorRejectsPlayingWithHandSizeNotMatchingProgress() {
        // No completed tricks → every hand should hold 10. Drop one card.
        var (hands, _) = dealHands()
        hands[north] = Array(hands[north]!.dropLast())
        let state = DealState.playing(playingFixture(hands: hands))
        // checkHands runs first (size 9 ≠ expected 10) — message uses "expected 10".
        assertViolation(state, contains: "expected 10")
    }

    func testValidatorRejectsPlayingWithTrickSumNotMatchingCompletedCount() {
        // Counts say 5 tricks have been won, but completedTricks is empty.
        let state = DealState.playing(playingFixture(
            trickCounts: [north: 3, east: 2, south: 0]
        ))
        assertViolation(state, contains: "trickCounts sum")
    }

    func testValidatorRejectsDealFinishedWithBadTrickCountsKeys() {
        let result = DealResult(
            kind: .allPass,
            activePlayers: seats,
            trickCounts: [north: 0, east: 0], // missing south
            completedTricks: [],
            scoreDelta: ScoreDelta(players: seats)
        )
        assertViolation(.dealFinished(result), contains: "trickCounts keys")
    }

    func testValidatorRejectsDealFinishedWithBadInitialHandsKeys() {
        let (hands, _) = dealHands()
        let result = DealResult(
            kind: .allPass,
            activePlayers: seats,
            trickCounts: [north: 10, east: 0, south: 0],
            completedTricks: [],
            scoreDelta: ScoreDelta(players: seats),
            initialHands: hands.filter { $0.key != south }
        )
        assertViolation(.dealFinished(result), contains: "initialHands keys")
    }

    // MARK: - Score invariants

    func testScoreSheetValidationRejectsUnknownPoolPlayer() {
        let ghost: PlayerID = "ghost"
        let score = ScoreSheet(
            uncheckedPlayers: seats,
            pool: [north: 0, east: 0, south: 0, ghost: 1],
            mountain: seats.dictionary(filledWith: 0),
            whists: seats.dictionary(filledWith: [:])
        )
        assertViolation(try score.validate(players: seats), contains: "score pool keys")
    }

    func testScoreDeltaValidationRejectsUnknownWhistTarget() {
        let ghost: PlayerID = "ghost"
        let delta = ScoreDelta(
            uncheckedPlayers: seats,
            pool: seats.dictionary(filledWith: 0),
            mountain: seats.dictionary(filledWith: 0),
            whists: [
                north: [ghost: 1],
                east: [:],
                south: [:],
            ]
        )
        assertViolation(try delta.validate(players: seats), contains: "unknown players")
    }

    func testScoreSheetValidationRejectsNegativePoolEntry() {
        let score = ScoreSheet(
            uncheckedPlayers: seats,
            pool: [north: -1, east: 0, south: 0],
            mountain: seats.dictionary(filledWith: 0),
            whists: seats.dictionary(filledWith: [:])
        )

        assertViolation(try score.validate(players: seats), contains: "pool entries cannot be negative")
    }

    func testScoreSheetValidationRejectsNegativeDirectWhistEntry() {
        let score = ScoreSheet(
            uncheckedPlayers: seats,
            pool: seats.dictionary(filledWith: 0),
            mountain: seats.dictionary(filledWith: 0),
            whists: [
                north: [east: -1],
                east: [:],
                south: [:],
            ]
        )

        assertViolation(try score.validate(players: seats), contains: "direct whist entries cannot be negative")
    }

    func testScoreDeltaValidationRejectsNegativePoolEntry() {
        let delta = ScoreDelta(
            uncheckedPlayers: seats,
            pool: [north: -1, east: 0, south: 0],
            mountain: seats.dictionary(filledWith: 0),
            whists: seats.dictionary(filledWith: [:])
        )

        assertViolation(try delta.validate(players: seats), contains: "pool entries cannot be negative")
    }

    func testScoreDeltaValidationRejectsNegativeDirectWhistEntry() {
        let delta = ScoreDelta(
            uncheckedPlayers: seats,
            pool: seats.dictionary(filledWith: 0),
            mountain: seats.dictionary(filledWith: 0),
            whists: [
                north: [east: -1],
                east: [:],
                south: [:],
            ]
        )

        assertViolation(try delta.validate(players: seats), contains: "direct whist entries cannot be negative")
    }

    func testScoreSheetDecodingRejectsNegativePoolEntry() throws {
        let score = ScoreSheet(
            uncheckedPlayers: seats,
            pool: [north: -1, east: 0, south: 0],
            mountain: seats.dictionary(filledWith: 0),
            whists: seats.dictionary(filledWith: [:])
        )
        let data = try JSONEncoder().encode(score)

        XCTAssertThrowsError(try JSONDecoder().decode(ScoreSheet.self, from: data)) { error in
            guard case let DecodingError.dataCorrupted(context) = error else {
                return XCTFail("Expected dataCorrupted; got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("pool entries cannot be negative"))
        }
    }

    func testScoreDeltaDecodingRejectsNegativeDirectWhistEntry() throws {
        let delta = ScoreDelta(
            uncheckedPlayers: seats,
            pool: seats.dictionary(filledWith: 0),
            mountain: seats.dictionary(filledWith: 0),
            whists: [
                north: [east: -1],
                east: [:],
                south: [:],
            ]
        )
        let data = try JSONEncoder().encode(delta)

        XCTAssertThrowsError(try JSONDecoder().decode(ScoreDelta.self, from: data)) { error in
            guard case let DecodingError.dataCorrupted(context) = error else {
                return XCTFail("Expected dataCorrupted; got \(error)")
            }
            XCTAssertTrue(context.debugDescription.contains("direct whist entries cannot be negative"))
        }
    }

    func testScoreDecodingPreservesLegitimateNegativeMountainRelief() throws {
        let score = ScoreSheet(
            uncheckedPlayers: seats,
            pool: seats.dictionary(filledWith: 1),
            mountain: [north: -1, east: 0, south: 0],
            whists: seats.dictionary(filledWith: [:])
        )
        let delta = ScoreDelta(
            uncheckedPlayers: seats,
            pool: seats.dictionary(filledWith: 0),
            mountain: [north: -1, east: 0, south: 0],
            whists: seats.dictionary(filledWith: [:])
        )

        let decodedScore = try JSONDecoder().decode(
            ScoreSheet.self,
            from: JSONEncoder().encode(score)
        )
        let decodedDelta = try JSONDecoder().decode(
            ScoreDelta.self,
            from: JSONEncoder().encode(delta)
        )

        XCTAssertEqual(decodedScore, score)
        XCTAssertEqual(decodedDelta, delta)
    }

    func testSnapshotValidatorRejectsScorePlayerMismatch() {
        let score = ScoreSheet(
            uncheckedPlayers: [north, east],
            pool: [north: 0, east: 0],
            mountain: [north: 0, east: 0],
            whists: [north: [:], east: [:]]
        )
        let snapshot = PreferansSnapshot(
            players: seats,
            rules: .sochi,
            state: .waitingForDeal,
            score: score,
            nextDealer: north
        )
        assertViolation(snapshot, contains: "score players")
    }

    func testSnapshotValidatorRejectsNegativeRaspasySeries() {
        let snapshot = PreferansSnapshot(
            players: seats,
            rules: .sochi,
            state: .waitingForDeal,
            score: ScoreSheet(players: seats),
            nextDealer: north,
            consecutiveAllPassDeals: -1
        )

        assertViolation(snapshot, contains: "consecutiveAllPassDeals cannot be negative")
    }

    func testSnapshotValidatorRejectsNegativeDealCount() {
        let snapshot = PreferansSnapshot(
            players: seats,
            rules: .sochi,
            state: .waitingForDeal,
            score: ScoreSheet(players: seats),
            nextDealer: north,
            dealsPlayed: -1
        )

        assertViolation(snapshot, contains: "dealsPlayed cannot be negative")
    }

    func testSnapshotValidatorRejectsMutatedRuleConfiguration() {
        var rules = PreferansRules.sochi
        rules.zeroTricksAllPassPoolBonus = -1
        let snapshot = PreferansSnapshot(
            players: seats,
            rules: rules,
            state: .waitingForDeal,
            score: ScoreSheet(players: seats),
            nextDealer: north
        )

        assertViolation(snapshot, contains: "invalid rules")
    }

    func testSnapshotValidatorRejectsNegativeDedicatedTotusBonus() {
        let snapshot = PreferansSnapshot(
            players: seats,
            rules: .sochi,
            match: MatchSettings(
                poolTarget: .max,
                totus: .dedicatedContract(requireWhist: true, bonusPool: -1)
            ),
            state: .waitingForDeal,
            score: ScoreSheet(players: seats),
            nextDealer: north
        )

        assertViolation(snapshot, contains: "bonus pool cannot be negative")
    }

    func testSnapshotValidatorRejectsGameOverSummaryMismatch() {
        let (hands, _) = dealHands()
        let score = ScoreSheet(
            uncheckedPlayers: seats,
            pool: [north: 1, east: 0, south: 0],
            mountain: seats.dictionary(filledWith: 0),
            whists: seats.dictionary(filledWith: [:])
        )
        let result = DealResult(
            kind: .allPass,
            activePlayers: seats,
            trickCounts: [north: 10, east: 0, south: 0],
            completedTricks: [],
            scoreDelta: ScoreDelta(players: seats),
            initialHands: hands
        )
        let balances = score.normalizedBalances()
        let standings = seats.map {
            MatchSummary.Standing(
                player: $0,
                balance: balances[$0] ?? 0,
                pool: score.pool[$0] ?? 0,
                mountain: score.mountain[$0] ?? 0
            )
        }
        let summary = MatchSummary(finalScore: score, dealsPlayed: 2, lastDeal: result, standings: standings)
        let snapshot = PreferansSnapshot(
            players: seats,
            rules: .sochi,
            match: MatchSettings(poolTarget: 1, poolClosure: .tableTotal),
            state: .gameOver(summary),
            score: score,
            nextDealer: north,
            dealsPlayed: 1
        )
        assertViolation(snapshot, contains: "gameOver dealsPlayed")
    }

    func testSnapshotValidatorRejectsGameOverBeforeSharedPoolTarget() {
        let (hands, _) = dealHands()
        let score = ScoreSheet(players: seats)
        let result = DealResult(
            kind: .allPass,
            activePlayers: seats,
            trickCounts: [north: 10, east: 0, south: 0],
            completedTricks: [],
            scoreDelta: ScoreDelta(players: seats),
            initialHands: hands
        )
        let standings = seats.map {
            MatchSummary.Standing(player: $0, balance: 0, pool: 0, mountain: 0)
        }
        let summary = MatchSummary(finalScore: score, dealsPlayed: 1, lastDeal: result, standings: standings)
        let snapshot = PreferansSnapshot(
            players: seats,
            rules: .leningrad,
            match: MatchSettings(poolTarget: 1, poolClosure: .tableTotal),
            state: .gameOver(summary),
            score: score,
            nextDealer: north,
            dealsPlayed: 1
        )

        assertViolation(snapshot, contains: "gameOver score must satisfy")
    }

    func testSnapshotValidatorRejectsOpenStateWithClosedIndividualPulka() {
        let score = ScoreSheet(
            uncheckedPlayers: seats,
            pool: seats.dictionary(filledWith: 1),
            mountain: seats.dictionary(filledWith: 0),
            whists: seats.dictionary(filledWith: [:])
        )
        let snapshot = PreferansSnapshot(
            players: seats,
            rules: .sochi,
            match: MatchSettings(poolTarget: 3),
            state: .waitingForDeal,
            score: score,
            nextDealer: north
        )

        assertViolation(snapshot, contains: "open deal state cannot carry a closed pulka")
    }

    func testSnapshotValidatorRejectsIndividualPoolOvershoot() {
        let score = ScoreSheet(
            uncheckedPlayers: seats,
            pool: [north: 2, east: 0, south: 0],
            mountain: seats.dictionary(filledWith: 0),
            whists: seats.dictionary(filledWith: [:])
        )
        let snapshot = PreferansSnapshot(
            players: seats,
            rules: .sochi,
            match: MatchSettings(poolTarget: 3),
            state: .waitingForDeal,
            score: score,
            nextDealer: north
        )

        assertViolation(snapshot, contains: "individual pool entry exceeds its target")
    }
}
