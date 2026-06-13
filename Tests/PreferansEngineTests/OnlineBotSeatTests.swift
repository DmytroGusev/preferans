import XCTest
@testable import PreferansApp
@testable import PreferansEngine

/// Covers the host-driven online bot model: the `bot:` seat marker, the host
/// actor's bot-decision plan, the waiting-room roster, no-show conversion, and
/// the full autonomous play loop a host runs for its bot seats.
@MainActor
final class OnlineBotSeatTests: XCTestCase {
    // MARK: - Seat classification

    func testAccountPrefixClassifiesPendingBotAndRealSeats() {
        let bot = OnlinePeer(playerID: "east", accountID: "bot:east", provider: .dev, displayName: "Bot 2")
        XCTAssertTrue(bot.isBotSeat)
        XCTAssertFalse(bot.isPendingSeat)

        let pending = OnlinePeer(playerID: "south", accountID: "pending:south", provider: .dev, displayName: "South")
        XCTAssertTrue(pending.isPendingSeat)
        XCTAssertFalse(pending.isBotSeat)

        let human = OnlinePeer(playerID: "north", accountID: "apple:abc", provider: .apple, displayName: "North")
        XCTAssertFalse(human.isBotSeat)
        XCTAssertFalse(human.isPendingSeat)
    }

    // MARK: - HostGameActor bot decision plan

    func testHostActorReportsBotPlanOnlyForBotControlledSeats() async throws {
        let seats = ["north", "east", "south"].map {
            PlayerIdentity(playerID: PlayerID($0), gamePlayerID: $0, displayName: $0.capitalized)
        }
        let actor = try HostGameActor(
            tableID: UUID(),
            hostPlayerID: "north",
            seats: seats,
            dealSource: ScriptedDealSource(decks: [Deck.standard32])
        )

        // Before any deal, nobody is on the clock.
        let idlePlan = await actor.nextBotDecisionPlan(botSeats: ["north", "east", "south"])
        XCTAssertNil(idlePlan, "No seat owes a move in waitingForDeal.")

        // Start the deal so there is a current bidder.
        let start = ClientActionEnvelope(tableID: actor.tableID, actor: "north", action: .startDeal(dealer: nil, deck: nil), baseHostSequence: 0)
        _ = try await actor.applyClientAction(start, sender: "north")

        let bidder = try await currentBidder(of: actor)

        // The bidder is a bot ⇒ a plan is returned naming that decider.
        let botPlan = await actor.nextBotDecisionPlan(botSeats: [bidder])
        XCTAssertEqual(botPlan?.decider, bidder)

        // The bidder is human (not in botSeats) ⇒ no plan.
        let everySeat: Set<PlayerID> = ["north", "east", "south"]
        let humanPlan = await actor.nextBotDecisionPlan(botSeats: everySeat.subtracting([bidder]))
        XCTAssertNil(humanPlan, "A human-controlled seat must not be auto-played.")

        // stillAwaiting tracks the captured state.
        let plan = try XCTUnwrap(botPlan)
        let stillThere = await actor.stillAwaiting(plan.snapshot.state)
        XCTAssertTrue(stillThere)
        _ = try await actor.applyClientAction(
            ClientActionEnvelope(tableID: actor.tableID, actor: bidder, action: .bid(player: bidder, call: .pass), baseHostSequence: 1),
            sender: bidder
        )
        let movedOn = await actor.stillAwaiting(plan.snapshot.state)
        XCTAssertFalse(movedOn, "After an action the previously captured state is stale.")
    }

    func testHostActorIgnoresStaleDuplicateStartDealWithoutConsumingDeck() async throws {
        let seats = ["north", "east", "south"].map {
            PlayerIdentity(playerID: PlayerID($0), gamePlayerID: $0, displayName: $0.capitalized)
        }
        let source = CountingDealSource(decks: [Deck.standard32])
        let actor = try HostGameActor(
            tableID: UUID(),
            hostPlayerID: "north",
            seats: seats,
            dealSource: source
        )

        let first = ClientActionEnvelope(
            tableID: actor.tableID,
            actor: "north",
            action: .startDeal(dealer: nil, deck: nil),
            baseHostSequence: 0
        )
        let duplicate = ClientActionEnvelope(
            tableID: actor.tableID,
            actor: "north",
            action: .startDeal(dealer: nil, deck: nil),
            baseHostSequence: 0
        )

        let firstUpdate = try await actor.applyClientAction(first, sender: "north")
        let duplicateUpdate = try await actor.applyClientAction(duplicate, sender: "north")

        XCTAssertEqual(firstUpdate.sequence, 1)
        XCTAssertEqual(duplicateUpdate.sequence, 1)
        XCTAssertTrue(duplicateUpdate.events.isEmpty)
        XCTAssertNil(duplicateUpdate.validatedAction)
        XCTAssertEqual(source.requestCount, 1)
        guard case .bidding = duplicateUpdate.snapshot.state else {
            return XCTFail("Stale duplicate startDeal should leave the first deal in bidding.")
        }
    }

    // MARK: - Waiting-room roster

    func testRosterAndCanHostStartReflectOccupancyAndConversion() async throws {
        let peers = [
            OnlinePeer(playerID: "north", accountID: "apple:host", provider: .apple, displayName: "Host"),
            OnlinePeer(playerID: "east", accountID: "pending:east", provider: .dev, displayName: "East"),
            OnlinePeer(playerID: "south", accountID: "bot:south", provider: .dev, displayName: "Bot 3")
        ]
        let room = InMemoryRoom(peers: peers, hostPlayerID: "north")
        let host = RoomOnlineGameCoordinator(
            dealSource: ScriptedDealSource(decks: [Deck.standard32]),
            heartbeat: .disabled
        )
        await host.attach(transport: try room.transport(for: "north"))
        await pump(until: { host.rosterSeats.count == 3 })

        XCTAssertEqual(occupancy(of: "north", in: host), .you(name: "Host"))
        XCTAssertEqual(occupancy(of: "east", in: host), .openWaiting)
        XCTAssertTrue(occupancy(of: "south", in: host)?.isBot == true)
        XCTAssertFalse(host.canHostStart, "An open seat blocks Start.")

        await host.fillOpenSeatsWithBots()
        await pump(until: { host.canHostStart })

        XCTAssertTrue(occupancy(of: "east", in: host)?.isBot == true, "No-show seat is converted to a bot.")
        XCTAssertTrue(host.canHostStart, "Every seat is now human-or-bot.")

        host.startFirstDeal()
        await pump(until: { (host.projection?.sequence ?? 0) >= 1 })
        let eastSeat = try XCTUnwrap(host.projection?.seats.first { $0.player == "east" })
        XCTAssertTrue(
            eastSeat.displayName.hasPrefix("Bot"),
            "Botized seats must not keep placeholder names in live projections."
        )
        XCTAssertNotEqual(eastSeat.displayName, "East")

        host.detach()
    }

    func testStartFirstDealRejectsOpenSeats() async throws {
        let peers = [
            OnlinePeer(playerID: "north", accountID: "apple:host", provider: .apple, displayName: "Host"),
            OnlinePeer(playerID: "east", accountID: "pending:east", provider: .dev, displayName: "East"),
            OnlinePeer(playerID: "south", accountID: "bot:south", provider: .dev, displayName: "Bot 3")
        ]
        let room = InMemoryRoom(peers: peers, hostPlayerID: "north")
        let host = RoomOnlineGameCoordinator(
            dealSource: ScriptedDealSource(decks: [Deck.standard32]),
            heartbeat: .disabled
        )
        await host.attach(transport: try room.transport(for: "north"))
        await pump(until: { host.rosterSeats.count == 3 })

        host.startFirstDeal()
        for _ in 0..<5 { await Task.yield() }

        XCTAssertEqual(host.projection?.sequence, 0)
        XCTAssertEqual(
            host.errorText,
            "Start is available once every seat is filled — invite a friend or fill the empty seats with bots."
        )
        host.detach()
    }

    func testLateJoinToBotizedSeatIsRejected() async throws {
        let peers = [
            OnlinePeer(playerID: "north", accountID: "apple:host", provider: .apple, displayName: "Host"),
            OnlinePeer(playerID: "east", accountID: "pending:east", provider: .dev, displayName: "East"),
            OnlinePeer(playerID: "south", accountID: "pending:south", provider: .dev, displayName: "South")
        ]
        let room = InMemoryRoom(peers: peers, hostPlayerID: "north")
        let host = RoomOnlineGameCoordinator(
            dealSource: ScriptedDealSource(decks: [Deck.standard32]),
            heartbeat: .disabled
        )
        await host.attach(transport: try room.transport(for: "north"))
        await pump(until: { host.rosterSeats.count == 3 })
        await host.fillOpenSeatsWithBots()
        await pump(until: { occupancy(of: "east", in: host)?.isBot == true })

        // A late human tries to claim the seat the host already gave to a bot.
        let lateTransport = try room.transport(for: "east")
        let hostPeer = try XCTUnwrap(peers.first { $0.playerID == "north" })
        let hello = GameWireMessage.hello(HelloEnvelope(
            tableID: host.tableID,
            player: PlayerIdentity(playerID: "east", gamePlayerID: "late-human", displayName: "Late"),
            lastSeenSequence: 0
        ))
        try await lateTransport.send(hello, to: [hostPeer], reliably: true)

        // Give the host a few turns of the run loop to process the hello.
        for _ in 0..<20 { await Task.yield() }

        XCTAssertTrue(occupancy(of: "east", in: host)?.isBot == true, "The bot keeps the seat; the late claim is rejected.")
        host.detach()
    }

    // MARK: - Full autonomous play

    func testHostDrivesEverySeatToDealFinishedWithoutHumanInput() async throws {
        // An all-bot table (e.g. an online "watch bots" room): the host alone
        // drives all three seats through bidding, talon, whist, and trick play.
        let peers = ["north", "east", "south"].map {
            OnlinePeer(playerID: PlayerID($0), accountID: "bot:\($0)", provider: .dev, displayName: $0.capitalized)
        }
        let room = InMemoryRoom(peers: peers, hostPlayerID: "north")
        let host = RoomOnlineGameCoordinator(
            dealSource: ScriptedDealSource(decks: [Deck.standard32]),
            heartbeat: .disabled,
            botMoveDelay: .zero
        )
        await host.attach(transport: try room.transport(for: "north"))
        await pump(until: { host.projection != nil })

        host.startFirstDeal()

        // The loop must advance the engine with zero human input.
        await pump(until: { (host.projection?.sequence ?? 0) >= 3 }, timeout: .seconds(5))

        // ...all the way to a scored deal.
        await pump(until: {
            if case .dealFinished = host.projection?.phase { return true }
            return false
        }, timeout: .seconds(30))

        guard case .dealFinished = try XCTUnwrap(host.projection).phase else {
            return XCTFail("Host-driven bots should play the deal to completion.")
        }
        XCTAssertNil(host.errorText, "Autonomous bot play must not surface errors. Got: \(host.errorText ?? "")")
        host.detach()
    }

    // MARK: - Helpers

    private func occupancy(of player: PlayerID, in coordinator: RoomOnlineGameCoordinator) -> WaitingRoomSeat.Occupancy? {
        coordinator.rosterSeats.first { $0.player == player }?.occupancy
    }

    private func currentBidder(of actor: HostGameActor) async throws -> PlayerID {
        let snapshot = await actor.currentSnapshot
        guard case let .bidding(state) = snapshot.state else {
            throw EngineTestError("Expected bidding, got \(snapshot.state).")
        }
        return state.currentPlayer
    }

    private func pump(
        until condition: @MainActor () -> Bool,
        timeout: Duration = .milliseconds(750),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            await Task.yield()
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }
}
