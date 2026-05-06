import XCTest
@testable import PreferansApp
@testable import PreferansEngine

/// Verifies the "lone whister pulls the passer's cards" rule that applies in
/// single-whist greedy scoring. The bug this guards against: the whister
/// could not play on the passer's turn, so a bot or human passer took the
/// trick into their own hands even though scoring rolls those tricks into
/// the whister anyway. The fix introduces a controlling-actor concept the
/// engine, projection, and bot dispatcher all share.
final class SingleWhistControlTests: AppTestCase {
    private let players: [PlayerID] = ["north", "east", "south"]

    // MARK: - Engine API

    func testControllingActorIsTheWhisterForThePasserDuringSingleWhistPlay() throws {
        let engine = try makeSingleWhistPlayingEngine(whister: "east", passer: "south")

        XCTAssertEqual(engine.controllingActor(of: "south"), "east", "the lone whister speaks for the passer")
        XCTAssertEqual(engine.controllingActor(of: "east"), "east", "the whister speaks for themselves")
        XCTAssertEqual(engine.controllingActor(of: "north"), "north", "the declarer is never controlled")
    }

    func testControlledSeatResolvesFromControllerWhenItIsThePassersTurn() throws {
        var engine = try makeSingleWhistPlayingEngine(whister: "east", passer: "south")

        try advanceToCurrentPlayer("south", in: &engine)

        XCTAssertEqual(engine.controlledSeat(by: "east"), "south")
        XCTAssertNil(engine.controlledSeat(by: "north"))
        XCTAssertNil(engine.controlledSeat(by: "south"))
    }

    func testLegalCardsForWhisterReturnsPasserHandWhenItIsThePassersTurn() throws {
        var engine = try makeSingleWhistPlayingEngine(whister: "east", passer: "south")
        try advanceToCurrentPlayer("south", in: &engine)
        guard case let .playing(playing) = engine.state else {
            return XCTFail("Expected playing state.")
        }
        let passerHand = Set(playing.hands["south"] ?? [])
        let whisterCards = Set(engine.legalCards(for: "east"))
        XCTAssertFalse(whisterCards.isEmpty, "whister must see playable cards on the passer's turn")
        XCTAssertTrue(whisterCards.isSubset(of: passerHand), "playable cards belong to the passer's hand")
        XCTAssertTrue(engine.legalCards(for: "south").isEmpty, "passer cannot tap their own cards while controlled")
    }

    func testGreedyScoringIsRequiredForControlTransfer() throws {
        var engine = try makeSingleWhistPlayingEngine(
            whister: "east",
            passer: "south",
            rules: PreferansRules(singleWhistScoring: .ownHandOnly)
        )
        try advanceToCurrentPlayer("south", in: &engine)
        XCTAssertEqual(engine.controllingActor(of: "south"), "south",
                       "ownHandOnly scoring keeps the passer in charge of their own cards")
    }

    // MARK: - Multiplayer host validation

    func testHostActorAllowsTheWhisterToSendPlayActionsForThePasser() async throws {
        let host = try await makeSingleWhistHostAtPasserTurn(declarer: "north", whister: "east", passer: "south")
        let snapshotState = await host.currentSnapshot.state
        guard case let .playing(playing) = snapshotState,
              playing.currentPlayer == "south",
              let card = playing.hands["south"]?.sorted().first else {
            return XCTFail("Expected south to be on lead with a card to play; got \(snapshotState.description).")
        }

        let tableID = await host.tableID
        let envelope = ClientActionEnvelope(
            tableID: tableID,
            actor: "south",
            action: .playCard(player: "south", card: card),
            baseHostSequence: 0
        )

        // The whister sends the action on behalf of the passer — the host
        // must accept it.
        _ = try await host.applyClientAction(envelope, sender: "east")
    }

    func testHostActorRejectsAnUnrelatedSenderClaimingToActForThePasser() async throws {
        let host = try await makeSingleWhistHostAtPasserTurn(declarer: "north", whister: "east", passer: "south")
        let snapshotState = await host.currentSnapshot.state
        guard case let .playing(playing) = snapshotState,
              playing.currentPlayer == "south",
              let card = playing.hands["south"]?.sorted().first else {
            return XCTFail("Expected south to be on lead.")
        }

        let tableID = await host.tableID
        let envelope = ClientActionEnvelope(
            tableID: tableID,
            actor: "south",
            action: .playCard(player: "south", card: card),
            baseHostSequence: 0
        )

        do {
            _ = try await host.applyClientAction(envelope, sender: "north")
            XCTFail("Declarer should not be able to act for the passer.")
        } catch let error as HostGameError {
            guard case .spoofedActor = error else {
                return XCTFail("Expected spoofedActor; got \(error)")
            }
        }
    }

    // MARK: - Projection

    func testProjectionRevealsPasserHandToTheControllingWhister() throws {
        var engine = try makeSingleWhistPlayingEngine(whister: "east", passer: "south")
        try advanceToCurrentPlayer("south", in: &engine)

        let projection = PlayerProjectionBuilder.projection(
            for: "east",
            tableID: UUID(),
            sequence: 0,
            engine: engine,
            policy: .online
        )

        let passerSeat = try XCTUnwrap(projection.seats.first { $0.player == "south" })
        XCTAssertEqual(passerSeat.hand.compactMap(\.knownCard).count, passerSeat.hand.count,
                       "controlling whister sees every card in the passer's hand")
        XCTAssertEqual(projection.legal.playableCardsOwner, "south",
                       "playable cards belong to the controlled passer's seat")
        XCTAssertFalse(projection.legal.playableCards.isEmpty,
                       "controlling whister can play on the passer's turn")
    }

    func testProjectionDoesNotLeakPasserHandToOtherViewers() throws {
        var engine = try makeSingleWhistPlayingEngine(whister: "east", passer: "south")
        try advanceToCurrentPlayer("south", in: &engine)

        let declarerProjection = PlayerProjectionBuilder.projection(
            for: "north",
            tableID: UUID(),
            sequence: 0,
            engine: engine,
            policy: .online
        )
        let passerSeatFromDeclarer = try XCTUnwrap(declarerProjection.seats.first { $0.player == "south" })
        XCTAssertEqual(passerSeatFromDeclarer.hand.compactMap(\.knownCard).count, 0,
                       "declarer must not gain visibility into the passer's hand")
    }

    // MARK: - Helpers

    private func makeSingleWhistPlayingEngine(
        whister: PlayerID,
        passer: PlayerID,
        rules: PreferansRules = .sochi
    ) throws -> PreferansEngine {
        let recipe = HandRecipe.declarerFails(
            declarer: "north",
            contract: GameContract(6, .suit(.diamonds)),
            declarerWillTake: 4
        )
        var engine = try PreferansEngine(players: players, rules: rules, firstDealer: "south")
        _ = try engine.apply(.startDeal(dealer: "south", deck: recipe.deck(for: players)))
        try EngineTestDriver.driveAuctionWinning(engine: &engine, declarer: "north", bid: .game(GameContract(6, .suit(.diamonds))))
        try EngineTestDriver.discardTalon(engine: &engine, declarer: "north")
        try EngineTestDriver.declareContract(engine: &engine, declarer: "north", contract: GameContract(6, .suit(.diamonds)))
        guard case let .awaitingWhist(whist) = engine.state else {
            throw EngineTestError("Expected awaitingWhist; got \(engine.state.description)")
        }
        let firstDefender = whist.defenders[0]
        let secondDefender = whist.defenders[1]
        XCTAssertEqual(Set([firstDefender, secondDefender]), Set([whister, passer]),
                       "fixture mismatch: whister/passer must be the two defenders")
        let firstCall: WhistCall = firstDefender == whister ? .whist : .pass
        let secondCall: WhistCall = secondDefender == whister ? .whist : .pass
        _ = try engine.apply(.whist(player: firstDefender, call: firstCall))
        _ = try engine.apply(.whist(player: secondDefender, call: secondCall))
        if case .awaitingDefenderMode = engine.state {
            _ = try engine.apply(.chooseDefenderMode(player: whister, mode: .closed))
        }
        guard case .playing = engine.state else {
            throw EngineTestError("Expected playing state after whist; got \(engine.state.description)")
        }
        return engine
    }

    private func advanceToCurrentPlayer(_ target: PlayerID, in engine: inout PreferansEngine) throws {
        var safety = 30
        while case let .playing(playing) = engine.state, playing.currentPlayer != target, safety > 0 {
            let actor = playing.currentPlayer
            // The controller picks the card; the action speaks for the
            // seat that owns the card. When the actor is the passer the
            // controller is the whister, so we always read legal cards
            // from the controller's perspective.
            let card = try XCTUnwrap(engine.legalCards(for: engine.controllingActor(of: actor)).min())
            _ = try engine.apply(.playCard(player: actor, card: card))
            safety -= 1
        }
        guard safety > 0 else {
            throw EngineTestError("Could not reach \(target)'s turn within step budget.")
        }
    }

    private func makeSingleWhistHostAtPasserTurn(
        declarer: PlayerID,
        whister: PlayerID,
        passer: PlayerID
    ) async throws -> HostGameActor {
        let recipe = HandRecipe.declarerFails(
            declarer: declarer,
            contract: GameContract(6, .suit(.diamonds)),
            declarerWillTake: 4
        )
        let seats = players.map { PlayerIdentity(playerID: $0, gamePlayerID: $0.rawValue, displayName: $0.rawValue) }
        let host = try HostGameActor(
            tableID: UUID(),
            hostPlayerID: declarer,
            seats: seats,
            rules: .sochi,
            firstDealer: "south",
            dealSource: ScriptedDealSource(decks: [recipe.deck(for: players)])
        )

        @Sendable func apply(_ action: PreferansAction, sender: PlayerID?) async throws {
            let tableID = host.tableID
            let envelope = ClientActionEnvelope(
                tableID: tableID,
                actor: action.actor ?? sender ?? declarer,
                action: action,
                baseHostSequence: 0
            )
            _ = try await host.applyClientAction(envelope, sender: sender)
        }

        try await apply(.startDeal(dealer: "south", deck: nil), sender: declarer)
        for player in players {
            let call: BidCall = player == declarer ? .bid(.game(GameContract(6, .suit(.diamonds)))) : .pass
            try await apply(.bid(player: player, call: call), sender: player)
        }
        let snap1 = await host.currentSnapshot
        guard case let .awaitingDiscard(exchange) = snap1.state else {
            throw EngineTestError("Expected awaitingDiscard; got \(snap1.state.description)")
        }
        try await apply(.discard(player: declarer, cards: exchange.talon), sender: declarer)
        let snapContract = await host.currentSnapshot
        if case .awaitingContract = snapContract.state {
            try await apply(.declareContract(player: declarer, contract: GameContract(6, .suit(.diamonds))), sender: declarer)
        }
        let snap2 = await host.currentSnapshot
        guard case let .awaitingWhist(whist) = snap2.state else {
            throw EngineTestError("Expected awaitingWhist; got \(snap2.state.description)")
        }
        for defender in whist.defenders {
            let call: WhistCall = defender == whister ? .whist : .pass
            try await apply(.whist(player: defender, call: call), sender: defender)
        }
        if case .awaitingDefenderMode = await host.currentSnapshot.state {
            try await apply(.chooseDefenderMode(player: whister, mode: .closed), sender: whister)
        }

        // Walk play forward until it's `passer`'s turn.
        while true {
            let snap = await host.currentSnapshot
            guard case let .playing(playing) = snap.state else {
                throw EngineTestError("Engine left playing before passer turn.")
            }
            if playing.currentPlayer == passer { return host }
            let actor = playing.currentPlayer
            let controller = playing.controllingActor(of: actor, rules: snap.rules)
            guard let card = playing.hands[actor]?.sorted().first(where: { card in
                // For declarer / whister own turn, just take a legal card.
                // We rebuild a transient engine to read legality.
                let engine = (try? PreferansEngine(snapshot: PreferansSnapshot(
                    players: snap.players,
                    rules: snap.rules,
                    state: snap.state,
                    score: snap.score,
                    nextDealer: snap.nextDealer
                )))
                guard let engine else { return true }
                return engine.legalCards(for: controller).contains(card)
            }) else {
                throw EngineTestError("No legal card for \(actor) under controller \(controller).")
            }
            try await apply(.playCard(player: actor, card: card), sender: controller)
        }
    }
}
