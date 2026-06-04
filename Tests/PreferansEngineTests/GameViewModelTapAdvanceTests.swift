import Clocks
import Dependencies
import XCTest
@testable import PreferansApp
@testable import PreferansEngine

@MainActor
final class GameViewModelTapAdvanceTests: AppTestCase {
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

    /// Drives the scripted deal into a misère, where every seat at the table
    /// may offer a settlement. A misère has no whist phase, so play begins
    /// straight after the declarer discards.
    private func driveToMiserePlay(_ model: GameViewModel) {
        model.tapToAdvanceEnabled = false
        model.startDeal()
        model.send(.bid(player: "north", call: .bid(.misere)))
        model.send(.bid(player: "east", call: .pass))
        model.send(.bid(player: "south", call: .pass))
        guard case let .awaitingDiscard(exchange) = model.engine.state else {
            return XCTFail("expected awaitingDiscard, got \(model.engine.state.description)")
        }
        model.send(.discard(player: "north", cards: exchange.talon))
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

    func testIdleHintFiresAfterDelayElapsesOnTestClock() async throws {
        // Verifies the time-driven escalation that the zero-delay shortcut
        // above can't actually exercise. With a `TestClock` we can advance
        // virtual time deterministically and observe the published flag flip.
        let testClock = TestClock()
        let model = try withDependencies {
            $0.continuousClock = testClock
        } operation: {
            let model = try makeModel()
            model.idleHintDelay = .seconds(4)
            driveToPlay(model)

            model.send(.playCard(player: "north", card: Card(.spades, .ace)))
            model.send(.playCard(player: "east", card: Card(.spades, .seven)))
            model.send(.playCard(player: "south", card: Card(.clubs, .seven)))
            return model
        }

        XCTAssertNotNil(model.pendingAdvance, "trick close should freeze the felt")
        XCTAssertFalse(model.idleHintActive,
                       "the prominent hint should not fire before the delay elapses")

        await testClock.advance(by: .seconds(4))
        // Yield once so the hint task's continuation runs to completion.
        await Task.yield()

        XCTAssertTrue(model.idleHintActive,
                      "after the delay elapses on the test clock the hint should be up")
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

    func testViewerSelfPlayDoesNotFireGateEvenWithBotsBehind() throws {
        let model = try makeModel()
        model.botStrategies["east"] = InertStrategy()
        model.botStrategies["south"] = InertStrategy()
        // Park the bot move delay so the bot scheduler can't race the
        // assertion if the gate-skip path schedules a follow-up move.
        model.botMoveDelay = .seconds(60)
        driveToPlay(model)

        model.send(.playCard(player: "north", card: Card(.spades, .ace)))

        XCTAssertNil(model.pendingAdvance,
                     "viewer's own card play never freezes — they just chose it")
    }

    func testBotCardPlayDoesNotFreezeFeltMidTrickWhenAnotherBotIsNext() throws {
        let model = try makeModel()
        model.botStrategies["east"] = InertStrategy()
        model.botStrategies["south"] = InertStrategy()
        model.botMoveDelay = .seconds(60)
        driveToPlay(model)

        // North leads, East (bot) replies. South (also bot) is up next,
        // but the gate should wait for the completed trick instead of
        // asking the user to acknowledge every bot card.
        model.send(.playCard(player: "north", card: Card(.spades, .ace)))
        XCTAssertNil(model.pendingAdvance, "viewer self-play sanity check")
        model.send(.playCard(player: "east", card: Card(.spades, .seven)))

        XCTAssertNil(model.pendingAdvance,
                     "mid-trick bot cards should advance on bot pacing; the completed trick is the tap point")
    }

    func testBotClosingCardFreezesCompletedTrick() throws {
        let model = try makeModel()
        model.botStrategies["east"] = InertStrategy()
        model.botStrategies["south"] = InertStrategy()
        model.botMoveDelay = .seconds(60)
        driveToPlay(model)

        model.send(.playCard(player: "north", card: Card(.spades, .ace)))
        model.send(.playCard(player: "east", card: Card(.spades, .seven)))
        XCTAssertNil(model.pendingAdvance)
        model.send(.playCard(player: "south", card: Card(.clubs, .seven)))

        let pending = try XCTUnwrap(model.pendingAdvance,
                                    "the final card of the trick should freeze the completed trick")
        XCTAssertEqual(pending.trickPlays?.count, 3)
        XCTAssertEqual(model.displayProjection().currentTrick.count, 3)
    }

    func testBotCardPlayDoesNotFreezeWhenViewerIsNext() throws {
        let model = try makeModel()
        // Pin the viewer to south so after east (bot) plays second, the
        // viewer is the next actor — the gate must stay quiet because
        // the viewer's own play will be the advance.
        model.botStrategies["east"] = InertStrategy()
        model.botMoveDelay = .seconds(60)
        model.selectedViewer = "south"
        driveToPlay(model)

        // North (declarer) leads. East (bot) follows. Viewer (south) is next.
        model.send(.playCard(player: "north", card: Card(.spades, .ace)))
        model.send(.playCard(player: "east", card: Card(.spades, .seven)))

        XCTAssertNil(model.pendingAdvance,
                     "no freeze when the viewer is up next — their own tap is the advance")
    }

    func testPrikupRevealFreezesForDefenderViewer() throws {
        let model = try makeModel()
        // Pinned viewer is north (default in makeModel). Drive an
        // auction where east wins so north is a defender — the prikup
        // reveal should freeze on the viewer.
        model.botStrategies["east"] = InertStrategy()
        model.botStrategies["south"] = InertStrategy()
        model.botMoveDelay = .seconds(60)
        model.startDeal()
        model.send(.bid(player: "north", call: .pass))
        model.send(.bid(player: "east", call: .bid(Self.sixSpades)))
        model.send(.bid(player: "south", call: .pass))

        let pending = try XCTUnwrap(model.pendingAdvance,
                                    "prikup reveal should freeze for defender viewers")
        XCTAssertEqual(pending.waitingOn, "north")
        XCTAssertNil(pending.trickPlays, "prikup gate has no trick override")
    }

    func testPrikupRevealDoesNotFreezeForDeclarerViewer() throws {
        let model = try makeModel()
        // Default viewer (north) wins the auction in driveToPlay's first
        // three sends. The declarer is the viewer, so no prikup gate.
        model.startDeal()
        model.send(.bid(player: "north", call: .bid(Self.sixSpades)))
        model.send(.bid(player: "east", call: .pass))
        model.send(.bid(player: "south", call: .pass))

        XCTAssertNil(model.pendingAdvance,
                     "the declarer is about to discard interactively — no extra acknowledgement tap")
    }

    func testLocalAgreementSettlementScoresDealWithoutSeatSwitching() throws {
        let model = try makeModel()
        driveToMiserePlay(model)

        let settlement = try XCTUnwrap(model.engine.legalSettlements(for: "north").first)

        model.settleByLocalAgreement(proposer: "north", settlement: settlement)

        XCTAssertNil(model.lastError)
        XCTAssertEqual(model.selectedViewer, "north",
                       "local board settlement should not require rotating the visible seat")
        XCTAssertTrue(model.recentEvents.contains(.settlementProposed(
            TrickSettlementProposal(proposer: "north", settlement: settlement, acceptedBy: ["north"])
        )))
        XCTAssertTrue(model.recentEvents.contains(.settlementAccepted(player: "east")))
        XCTAssertTrue(model.recentEvents.contains(.settlementAccepted(player: "south")))
        XCTAssertTrue(model.recentEvents.contains(.playSettled(settlement)))
        guard case let .dealFinished(result) = model.engine.state else {
            return XCTFail("expected the local agreement to score the deal")
        }
        XCTAssertEqual(result.settlement, settlement)
        XCTAssertTrue(result.completedTricks.isEmpty,
                      "an agreement settles the unplayed tricks rather than fabricating them")
    }
}

/// No-op strategy so test seats can be marked as bots without the
/// bot scheduler interfering with the manually-driven action sequence.
private struct InertStrategy: PlayerStrategy {
    func decide(snapshot: PreferansSnapshot, viewer: PlayerID) async -> PreferansAction? {
        nil
    }
}
