import XCTest
@testable import PreferansApp
@testable import PreferansEngine

@MainActor
final class GameViewModelTapAdvanceTests: XCTestCase {
    private static let sixSpades = ContractBid.game(GameContract(6, .suit(.spades)))

    private func makeModel() throws -> GameViewModel {
        try GameViewModel(
            players: ["north", "east", "south"],
            rules: .sochi,
            firstDealer: "south",
            viewerPolicy: .pinned("north"),
            dealSource: ScriptedDealSource(decks: DealScenario.northBidsSpadesSix.decks)
        )
    }

    private func driveToPlay(_ model: GameViewModel) {
        model.startDeal()
        model.send(.bid(player: "north", call: .bid(Self.sixSpades)))
        model.send(.bid(player: "east", call: .pass))
        model.send(.bid(player: "south", call: .pass))
        guard case let .awaitingDiscard(exchange) = model.engine.state else {
            return XCTFail("expected awaitingDiscard, got \(model.engine.state.description)")
        }
        model.send(.discard(player: "north", cards: exchange.talon))
        model.send(.declareContract(player: "north", contract: GameContract(6, .suit(.spades))))
        model.send(.whist(player: "east", call: .whist))
        model.send(.whist(player: "south", call: .whist))
    }

    func testMidTrickAllHumanPlayDoesNotFireTheGate() throws {
        let model = try makeModel()
        driveToPlay(model)

        model.send(.playCard(player: "north", card: Card(.spades, .ace)))

        XCTAssertNil(model.pendingAdvance,
                     "all-human mid-trick play should not freeze the felt — the device passes naturally")
    }

    func testTrickCloseFreezesTheFeltOnAllFourPlays() throws {
        let model = try makeModel()
        driveToPlay(model)

        model.send(.playCard(player: "north", card: Card(.spades, .ace)))
        model.send(.playCard(player: "east", card: Card(.spades, .seven)))
        model.send(.playCard(player: "south", card: Card(.clubs, .seven)))

        let pending = try XCTUnwrap(model.pendingAdvance, "trick close should freeze the felt")
        XCTAssertEqual(pending.trickPlays?.count, 3,
                       "three-player trick close stores all three plays")
        XCTAssertEqual(pending.trickWinner, "north",
                       "frozen view names the trick winner so counts can be rolled back")
    }

    func testDisplayProjectionRollsBackTrickCountWhileFrozen() throws {
        let model = try makeModel()
        driveToPlay(model)

        model.send(.playCard(player: "north", card: Card(.spades, .ace)))
        model.send(.playCard(player: "east", card: Card(.spades, .seven)))
        model.send(.playCard(player: "south", card: Card(.clubs, .seven)))

        let display = model.displayProjection()
        XCTAssertEqual(display.currentTrick.count, 3,
                       "frozen trick should still show three cards on the felt")
        XCTAssertEqual(display.trickCounts["north"], 0,
                       "winner's count is rolled back to its pre-close value while frozen")
        let liveProjection = model.projection()
        XCTAssertEqual(liveProjection.trickCounts["north"], 1,
                       "live projection still reflects the engine's true post-clear state")
    }

    func testAdvanceReleasesTheFreeze() throws {
        let model = try makeModel()
        driveToPlay(model)

        model.send(.playCard(player: "north", card: Card(.spades, .ace)))
        model.send(.playCard(player: "east", card: Card(.spades, .seven)))
        model.send(.playCard(player: "south", card: Card(.clubs, .seven)))
        XCTAssertNotNil(model.pendingAdvance)

        model.advance()

        XCTAssertNil(model.pendingAdvance, "advance() drops the freeze")
        XCTAssertFalse(model.idleHintActive, "advance() resets the idle escalation flag")
        XCTAssertEqual(model.displayProjection().currentTrick, [],
                       "post-advance display matches the live engine state")
    }

    func testGateIsBypassedWhenDisabled() throws {
        let model = try makeModel()
        model.tapToAdvanceEnabled = false
        driveToPlay(model)

        model.send(.playCard(player: "north", card: Card(.spades, .ace)))
        model.send(.playCard(player: "east", card: Card(.spades, .seven)))
        model.send(.playCard(player: "south", card: Card(.clubs, .seven)))

        XCTAssertNil(model.pendingAdvance,
                     "with the gate off the engine cascades exactly as it always did")
    }

    func testIdleHintFiresImmediatelyWhenDelayIsZero() throws {
        let model = try makeModel()
        // A zero delay flips `idleHintActive` synchronously inside
        // `startIdleHintTimer`, which lets the test assert the
        // escalation behaviour without sleeping or polling.
        model.idleHintDelay = .zero
        driveToPlay(model)

        model.send(.playCard(player: "north", card: Card(.spades, .ace)))
        model.send(.playCard(player: "east", card: Card(.spades, .seven)))
        model.send(.playCard(player: "south", card: Card(.clubs, .seven)))

        XCTAssertNotNil(model.pendingAdvance)
        XCTAssertTrue(model.idleHintActive,
                      "with a zero idle delay the prominent hint should already be up")
    }

    func testFreezeSuppressesPlayableCardsForViewer() throws {
        let model = try makeModel()
        // Pinned to north so the viewer is also the trick winner once the
        // trick closes. Without the suppression in displayProjection the
        // viewer could tap a card and skip the freeze.
        driveToPlay(model)

        model.send(.playCard(player: "north", card: Card(.spades, .ace)))
        model.send(.playCard(player: "east", card: Card(.spades, .seven)))
        model.send(.playCard(player: "south", card: Card(.clubs, .seven)))

        let display = model.displayProjection()
        XCTAssertTrue(display.legal.playableCards.isEmpty,
                      "frozen view never offers playable cards — first tap acknowledges the beat")
    }
}
