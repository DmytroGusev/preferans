import XCTest
@testable import PreferansApp
import PreferansEngine

final class ProjectionTests: XCTestCase {
    func testBiddingProjectionDoesNotLeakOtherHandsOrTalon() throws {
        let players: [PlayerID] = ["north", "east", "south"]
        var engine = try PreferansEngine(players: players, rules: .sochi, firstDealer: "south")
        _ = try engine.apply(.startDeal(dealer: "south", deck: Deck.standard32))

        let projection = PlayerProjectionBuilder.projection(
            for: "north",
            tableID: UUID(),
            sequence: 0,
            engine: engine,
            policy: .online
        )

        let north = try XCTUnwrap(projection.seats.first { $0.player == "north" })
        XCTAssertEqual(north.hand.compactMap(\.knownCard).count, 10)

        for seat in projection.seats where seat.player != "north" && seat.isActive {
            XCTAssertEqual(seat.hand.count, 10)
            XCTAssertTrue(seat.hand.allSatisfy { $0.knownCard == nil })
        }

        XCTAssertEqual(projection.talon.count, 2)
        XCTAssertTrue(projection.talon.allSatisfy { $0.knownCard == nil })
    }

    func testTalonRevealedToAllViewersDuringExchange() throws {
        let players: [PlayerID] = ["north", "east", "south"]
        var engine = try PreferansEngine(players: players, rules: .sochi, firstDealer: "south")
        _ = try engine.apply(.startDeal(dealer: "south", deck: Deck.standard32))

        try EngineTestDriver.driveAuctionWinning(
            engine: &engine,
            declarer: "north",
            bid: .game(GameContract(6, .suit(.spades)))
        )

        guard case .awaitingDiscard = engine.state else {
            return XCTFail("Expected awaitingDiscard after auction; got \(engine.state.description)")
        }

        for viewer in players {
            let projection = PlayerProjectionBuilder.projection(
                for: viewer,
                tableID: UUID(),
                sequence: 0,
                engine: engine,
                policy: .online
            )
            XCTAssertEqual(projection.talon.count, 2)
            XCTAssertTrue(
                projection.talon.allSatisfy { $0.knownCard != nil },
                "Talon should be revealed to \(viewer) during the exchange so every player can see what the declarer took."
            )
        }
    }

    func testLeadSuitAllPassProjectionKeepsTalonPublicToTable() throws {
        let players: [PlayerID] = ["north", "east", "south"]
        let recipe = HandRecipe.raspasyCleanExit(cleaner: "north", talonLeadSuit: .clubs)
        var engine = try PreferansEngine(
            players: players,
            rules: .sochiWithTalonLedAllPass,
            firstDealer: "south"
        )
        _ = try engine.apply(.startDeal(dealer: "south", deck: recipe.deck(for: players)))
        try EngineTestDriver.passOutAuction(engine: &engine)

        try assertPublicTalon(in: engine, viewers: players, label: "opening all-pass")

        while case let .playing(state) = engine.state, state.completedTricks.count < 1 {
            let actor = state.currentPlayer
            let card = try XCTUnwrap(engine.legalCards(for: actor).min())
            _ = try engine.apply(.playCard(player: actor, card: card))
        }

        try assertPublicTalon(in: engine, viewers: players, label: "second talon-led trick")
    }

    func testMisereProjectionRevealsDefenderHandsToDeclarer() throws {
        let players: [PlayerID] = ["north", "east", "south"]
        var engine = try PreferansEngine(players: players, rules: .sochi, firstDealer: "south")
        let deck = HandRecipe.cleanMisere(declarer: "north")
            .deck(for: engine.activePlayers(forDealer: "south"))
        _ = try engine.apply(.startDeal(dealer: "south", deck: deck))

        try EngineTestDriver.driveAuctionWinning(engine: &engine, declarer: "north", bid: .misere)
        try EngineTestDriver.discardTalon(engine: &engine, declarer: "north")

        guard case .playing = engine.state else {
            return XCTFail("Expected playing.misere; got \(engine.state.description)")
        }

        let projection = PlayerProjectionBuilder.projection(
            for: "north",
            tableID: UUID(),
            sequence: 0,
            engine: engine,
            policy: .online
        )

        for defender in ["east", "south"] as [PlayerID] {
            let seat = try XCTUnwrap(projection.seats.first { $0.player == defender })
            XCTAssertEqual(seat.role, .whister)
            XCTAssertEqual(seat.hand.count, 10)
            XCTAssertEqual(
                seat.hand.compactMap(\.knownCard).count,
                10,
                "Misère should reveal defender hands to the declarer."
            )
        }
    }

    func testStalingradProjectionKeepsForcedWhistHandsClosed() throws {
        let players: [PlayerID] = ["north", "east", "south"]
        var engine = try PreferansEngine(players: players, rules: .sochi, firstDealer: "north")
        _ = try engine.apply(.startDeal(dealer: "north", deck: Deck.standard32))

        _ = try engine.apply(.bid(player: "east", call: .bid(.game(GameContract(6, .suit(.spades))))))
        _ = try engine.apply(.bid(player: "south", call: .pass))
        _ = try engine.apply(.bid(player: "north", call: .pass))
        guard case let .awaitingDiscard(exchange) = engine.state else {
            return XCTFail("Expected discard.")
        }
        let discard = Array(((exchange.hands["east"] ?? []) + exchange.talon).prefix(2))
        _ = try engine.apply(.discard(player: "east", cards: discard))
        _ = try engine.apply(.declareContract(player: "east", contract: GameContract(6, .suit(.spades))))
        _ = try engine.apply(.whist(player: "south", call: .whist))
        _ = try engine.apply(.whist(player: "north", call: .whist))

        let projection = PlayerProjectionBuilder.projection(
            for: "east",
            tableID: UUID(),
            sequence: 0,
            engine: engine,
            policy: .online
        )

        for defender in ["south", "north"] as [PlayerID] {
            let seat = try XCTUnwrap(projection.seats.first { $0.player == defender })
            XCTAssertEqual(seat.role, .whister)
            XCTAssertEqual(seat.hand.count, 10)
            XCTAssertTrue(
                seat.hand.allSatisfy { $0.knownCard == nil },
                "Stalingrad forced whist must stay closed; it should not use open-whist projection."
            )
        }
    }

    func testPlayingProjectionHandVisibilityInvariantForAllGameContracts() throws {
        for contract in GameContract.allStandard {
            let closed = try makePlayingProjectionEngine(
                recipe: .declarerWins(declarer: "north", contract: contract),
                kind: .game(
                    GamePlayContext(
                        declarer: "north",
                        contract: contract,
                        defenders: ["east", "south"],
                        whisters: ["east", "south"],
                        defenderPlayMode: .closed,
                        whistCalls: [
                            WhistCallRecord(player: "east", call: .whist),
                            WhistCallRecord(player: "south", call: .whist)
                        ]
                    )
                )
            )
            assertPlayingHandVisibility(
                in: closed,
                openedPlayers: [],
                label: "\(contract) closed"
            )

            guard contract != GameContract(6, .suit(.spades)) else {
                continue
            }
            let open = try makePlayingProjectionEngine(
                recipe: .declarerWins(declarer: "north", contract: contract),
                kind: .game(
                    GamePlayContext(
                        declarer: "north",
                        contract: contract,
                        defenders: ["east", "south"],
                        whisters: ["east"],
                        defenderPlayMode: .open,
                        whistCalls: [
                            WhistCallRecord(player: "east", call: .whist),
                            WhistCallRecord(player: "south", call: .pass)
                        ]
                    )
                )
            )
            assertPlayingHandVisibility(
                in: open,
                openedPlayers: ["east", "south"],
                label: "\(contract) open"
            )
        }
    }

    func testPlayingProjectionHandVisibilityInvariantForMisereAndAllPass() throws {
        let misere = try makePlayingProjectionEngine(
            recipe: .cleanMisere(declarer: "north"),
            kind: .misere(MiserePlayContext(declarer: "north"))
        )
        assertPlayingHandVisibility(
            in: misere,
            openedPlayers: ["east", "south"],
            label: "misere"
        )

        let allPass = try makePlayingProjectionEngine(
            recipe: .raspasyCleanExit(cleaner: "north", talonLeadSuit: nil),
            kind: .allPass(AllPassPlayContext(talonPolicy: .ignored)),
            discard: []
        )
        assertPlayingHandVisibility(
            in: allPass,
            openedPlayers: [],
            label: "all-pass"
        )
    }

    func testFourPlayerDealerProjectsAsSittingOut() throws {
        let players: [PlayerID] = ["north", "east", "south", "west"]
        var engine = try PreferansEngine(players: players, rules: .sochi, firstDealer: "north")
        _ = try engine.apply(.startDeal(dealer: "north", deck: Deck.standard32))

        let projection = PlayerProjectionBuilder.projection(
            for: "east",
            tableID: UUID(),
            sequence: 0,
            engine: engine,
            policy: .online
        )

        let dealer = try XCTUnwrap(projection.seats.first { $0.player == "north" })
        XCTAssertTrue(dealer.isDealer)
        XCTAssertFalse(dealer.isActive)
        XCTAssertEqual(dealer.role, .sittingOut)

        for player in players where player != "north" {
            let seat = try XCTUnwrap(projection.seats.first { $0.player == player })
            XCTAssertTrue(seat.isActive, "\(player) should take part in a deal where north deals.")
            XCTAssertNotEqual(seat.role, .sittingOut, "\(player) should not be marked sitting out.")
        }
    }

    func testActionRoundTripsThroughJSON() throws {
        let action = PreferansAction.bid(
            player: "north",
            call: .bid(.game(GameContract(6, .suit(.spades))))
        )
        let encoded = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(PreferansAction.self, from: encoded)
        XCTAssertEqual(decoded, action)
    }

    func testHostStartDealStoresExplicitDeckForReplay() async throws {
        let seats = ["north", "east", "south"].map { PlayerIdentity(playerID: PlayerID($0), gamePlayerID: $0, displayName: $0) }
        let host = try HostGameActor(hostPlayerID: "north", seats: seats, firstDealer: "south")
        let envelope = ClientActionEnvelope(
            tableID: host.tableID,
            actor: "north",
            action: .startDeal(dealer: nil, deck: nil),
            baseHostSequence: 0
        )
        let update = try await host.applyClientAction(envelope, sender: "north")
        let record = try XCTUnwrap(update.validatedAction)
        guard case let .startDeal(dealer, deck) = record.action else {
            return XCTFail("Expected startDeal")
        }
        XCTAssertEqual(dealer, "south")
        XCTAssertEqual(deck?.count, 32)
    }

    private func makePlayingProjectionEngine(
        recipe: HandRecipe,
        kind: PlayKind,
        discard suppliedDiscard: [Card]? = nil
    ) throws -> PreferansEngine {
        let players: [PlayerID] = ["north", "east", "south"]
        let deck = recipe.deck(for: players)
        let deal = DealDeckLayout.deal(deck: deck, activePlayers: players)
        let discard = suppliedDiscard ?? deal.talon
        let playing = PlayingState(
            dealer: "south",
            activePlayers: players,
            hands: deal.hands,
            talon: deal.talon,
            discard: discard,
            leader: players[0],
            currentPlayer: players[0],
            kind: kind
        )
        return try PreferansEngine(
            snapshot: PreferansSnapshot(
                players: players,
                rules: .sochi,
                state: .playing(playing),
                score: ScoreSheet(players: players),
                nextDealer: "north"
            )
        )
    }

    private func assertPlayingHandVisibility(
        in engine: PreferansEngine,
        openedPlayers: Set<PlayerID>,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for viewer in engine.players {
            let projection = PlayerProjectionBuilder.projection(
                for: viewer,
                tableID: UUID(),
                sequence: 0,
                engine: engine,
                policy: .online
            )

            for seat in projection.seats where seat.isActive {
                let shouldSeeHand = seat.player == viewer || openedPlayers.contains(seat.player)
                let knownCount = seat.hand.compactMap(\.knownCard).count
                XCTAssertEqual(seat.hand.count, 10, "\(label): \(seat.player) should project ten cards.", file: file, line: line)
                if shouldSeeHand {
                    XCTAssertEqual(knownCount, 10, "\(label): \(viewer) should see \(seat.player)'s hand.", file: file, line: line)
                } else {
                    XCTAssertEqual(knownCount, 0, "\(label): \(viewer) should not see \(seat.player)'s hand.", file: file, line: line)
                }
            }
        }
    }

    private func assertPublicTalon(
        in engine: PreferansEngine,
        viewers: [PlayerID],
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let expectedTalon: [Card]
        guard case let .playing(state) = engine.state else {
            throw EngineTestError("Expected playing state.")
        }
        expectedTalon = state.talon.sorted()

        for viewer in viewers {
            let projection = PlayerProjectionBuilder.projection(
                for: viewer,
                tableID: UUID(),
                sequence: 0,
                engine: engine,
                policy: .online
            )
            XCTAssertEqual(
                projection.talon.compactMap(\.knownCard),
                expectedTalon,
                "\(label): \(viewer) should see the public talon on the table.",
                file: file,
                line: line
            )
        }
    }
}
