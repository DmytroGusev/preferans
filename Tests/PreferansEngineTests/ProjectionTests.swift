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
}
