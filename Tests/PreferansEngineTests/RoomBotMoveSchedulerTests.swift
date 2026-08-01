import XCTest
@testable import PreferansApp
@testable import PreferansEngine
@testable import PreferansEngineTestSupport

@MainActor
final class RoomBotMoveSchedulerTests: AppTestCase {
    func testSchedulerBuildsOneEnvelopeWithPublicSafeInsight() async throws {
        let fixture = try await makeBiddingActor()
        let profile = BotProfile(difficulty: .expert, temperament: .bold)
        let strategy = ExplainingPassStrategy(profile: profile)
        let scheduler = RoomBotMoveScheduler(strategy: strategy, delay: .zero)
        var emitted: RoomBotMove?

        scheduler.schedule(
            hostActor: fixture.actor,
            tableID: fixture.actor.tableID,
            botSeats: Set(fixture.players)
        ) { move in
            emitted = move
        }
        await waitUntil { emitted != nil && !scheduler.hasActiveWork }

        let move = try XCTUnwrap(emitted)
        XCTAssertEqual(move.sender, fixture.bidder)
        XCTAssertEqual(move.envelope.actor, fixture.bidder)
        XCTAssertEqual(move.envelope.action, .bid(player: fixture.bidder, call: .pass))
        XCTAssertEqual(move.envelope.baseHostSequence, 1)
        XCTAssertEqual(
            move.insight,
            BotDecisionExplanation(
                actor: fixture.bidder,
                profile: profile,
                rationale: .auctionPass
            )
        )
    }

    func testSchedulerDropsDecisionWhenActorStateAdvancesWhileStrategyRuns() async throws {
        let fixture = try await makeBiddingActor()
        let strategy = GatedPassStrategy()
        let scheduler = RoomBotMoveScheduler(strategy: strategy, delay: .zero)
        var emitted: RoomBotMove?

        scheduler.schedule(
            hostActor: fixture.actor,
            tableID: fixture.actor.tableID,
            botSeats: Set(fixture.players)
        ) { move in
            emitted = move
        }
        await strategy.waitUntilStarted()

        _ = try await fixture.actor.applyClientAction(
            ClientActionEnvelope(
                tableID: fixture.actor.tableID,
                actor: fixture.bidder,
                action: .bid(player: fixture.bidder, call: .pass),
                baseHostSequence: 1
            ),
            sender: fixture.bidder
        )
        await strategy.release()
        await waitUntil { !scheduler.hasActiveWork }

        XCTAssertNil(emitted)
    }

    func testCancelInvalidatesAWaitingNonCooperativeStrategy() async throws {
        let fixture = try await makeBiddingActor()
        let strategy = GatedPassStrategy()
        let scheduler = RoomBotMoveScheduler(strategy: strategy, delay: .zero)
        var emitted: RoomBotMove?

        scheduler.schedule(
            hostActor: fixture.actor,
            tableID: fixture.actor.tableID,
            botSeats: Set(fixture.players)
        ) { move in
            emitted = move
        }
        await strategy.waitUntilStarted()

        scheduler.cancel()
        XCTAssertFalse(scheduler.isScheduled)
        XCTAssertTrue(scheduler.hasActiveWork)
        await strategy.release()
        await waitUntil { !scheduler.hasActiveWork }

        XCTAssertNil(emitted)
    }

    private func makeBiddingActor() async throws -> (
        actor: HostGameActor,
        players: [PlayerID],
        bidder: PlayerID
    ) {
        let players: [PlayerID] = ["north", "east", "south"]
        let actor = try HostGameActor(
            hostPlayerID: players[0],
            seats: players.map {
                PlayerIdentity(playerID: $0, gamePlayerID: "test:\($0.rawValue)", displayName: $0.rawValue)
            },
            dealSource: ScriptedDealSource(decks: [Deck.standard32])
        )
        _ = try await actor.applyClientAction(
            ClientActionEnvelope(
                tableID: actor.tableID,
                actor: players[0],
                action: .startDeal(dealer: nil, deck: nil),
                baseHostSequence: 0
            ),
            sender: players[0]
        )
        let snapshot = await actor.currentSnapshot
        guard case let .bidding(state) = snapshot.state else {
            throw EngineTestError("Expected bidding state, got \(snapshot.state).")
        }
        return (actor, players, state.currentPlayer)
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool,
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

private struct ExplainingPassStrategy: PlayerStrategy {
    var profile: BotProfile

    func decide(snapshot: PreferansSnapshot, viewer: PlayerID) async -> PreferansAction? {
        .bid(player: viewer, call: .pass)
    }

    func decision(snapshot: PreferansSnapshot, viewer: PlayerID) async -> StrategyDecision? {
        StrategyDecision(
            action: .bid(player: viewer, call: .pass),
            explanation: BotDecisionExplanation(
                actor: viewer,
                profile: profile,
                rationale: .auctionPass
            )
        )
    }
}

private actor GatedPassStrategy: PlayerStrategy {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var decisionContinuation: CheckedContinuation<Void, Never>?

    func decide(snapshot: PreferansSnapshot, viewer: PlayerID) async -> PreferansAction? {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { continuation in
            decisionContinuation = continuation
        }
        return .bid(player: viewer, call: .pass)
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func release() {
        let continuation = decisionContinuation
        decisionContinuation = nil
        continuation?.resume()
    }
}
