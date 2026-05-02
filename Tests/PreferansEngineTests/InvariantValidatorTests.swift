import XCTest
@testable import PreferansEngine

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
        passed: Set<PlayerID> = []
    ) -> BiddingState {
        let (hands, talon) = dealHands()
        let activeSeats = overrideSeats ?? seats
        return BiddingState(
            dealer: north,
            activePlayers: activeSeats,
            hands: overrideHands ?? hands,
            talon: overrideTalon ?? talon,
            currentPlayer: overrideCurrent ?? activeSeats[0],
            passed: passed
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

    private func assertViolation(
        _ state: DealState,
        contains needle: String,
        file: StaticString = #file,
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

    private func assertAccepts(_ state: DealState, file: StaticString = #file, line: UInt = #line) {
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
}
