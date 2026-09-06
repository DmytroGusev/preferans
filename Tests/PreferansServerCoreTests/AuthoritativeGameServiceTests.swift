import XCTest
@testable import PreferansEngine
@testable import PreferansServerCore

final class AuthoritativeGameServiceTests: XCTestCase {
    private let identities: [PlayerIdentity] = [
        .init(playerID: "north", gamePlayerID: "account:north", displayName: "North"),
        .init(playerID: "east", gamePlayerID: "account:east", displayName: "East"),
        .init(playerID: "south", gamePlayerID: "account:south", displayName: "South"),
    ]

    func testExchangeEventsDoNotExposeDiscardToOtherSeats() throws {
        let cards = Array(Deck.shuffled(seed: 7).prefix(2))
        let event = PreferansEvent.talonExchanged(declarer: "north", talon: cards, discard: cards)
        for viewer: PlayerID in ["east", "south", "west"] {
            XCTAssertEqual(OnlineEventProjection.events([event], for: viewer), [
                .talonExchanged(declarer: "north", talon: [], discard: [])
            ])
        }
        XCTAssertEqual(OnlineEventProjection.events([event], for: "north"), [event])
    }

    func testNonceCannotBeReusedForDifferentPayload() async throws {
        let created = try AuthoritativeGameService.create(.init(identities: identities), dealSeed: 1)
        let nonce = UUID()
        let first = try await AuthoritativeGameService.apply(.init(
            state: created.state, sender: "north", actor: "north",
            action: .startDeal(dealer: nil, deck: nil), clientNonce: nonce, baseSequence: 0
        ))
        do {
            _ = try await AuthoritativeGameService.apply(.init(
                state: first.state, sender: "north", actor: "north",
                action: .startDeal(dealer: "east", deck: nil), clientNonce: nonce, baseSequence: 0
            ))
            XCTFail("A command ID must bind its original payload")
        } catch let error as AuthoritativeGameError {
            XCTAssertEqual(error, .commandIDConflict)
        }
    }

    func testServerCreatesAndAdvancesAnAuthoritativeGame() async throws {
        let created = try AuthoritativeGameService.create(
            .init(identities: identities, firstDealer: "north"),
            tableID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            dealSeed: 42
        )
        XCTAssertEqual(created.sequence, 0)
        XCTAssertEqual(created.projections.count, 3)

        let nonce = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let advanced = try await AuthoritativeGameService.apply(.init(
            state: created.state,
            sender: "north",
            actor: "north",
            action: .startDeal(dealer: nil, deck: nil),
            clientNonce: nonce,
            baseSequence: 0
        ))

        XCTAssertEqual(advanced.sequence, 1)
        let state = try AuthoritativeGameService.decodeState(advanced.state)
        XCTAssertEqual(state.sequence, 1)
        XCTAssertEqual(state.generatedDealCount, 1)
        guard case .bidding = state.snapshot.state else {
            return XCTFail("The authoritative engine should have started bidding.")
        }

        let north = try XCTUnwrap(advanced.projections.first { $0.viewer == "north" })
        let northSeat = try XCTUnwrap(north.projection.seats.first { $0.player == "north" })
        let eastSeat = try XCTUnwrap(north.projection.seats.first { $0.player == "east" })
        XCTAssertTrue(northSeat.hand.allSatisfy { $0.knownCard != nil })
        XCTAssertTrue(eastSeat.hand.allSatisfy { $0 == .hidden })
    }

    func testAuthenticatedSenderCannotClaimAnotherActor() async throws {
        let created = try AuthoritativeGameService.create(
            .init(identities: identities, firstDealer: "north"),
            dealSeed: 7
        )

        do {
            _ = try await AuthoritativeGameService.apply(.init(
                state: created.state,
                sender: "east",
                actor: "north",
                action: .startDeal(dealer: nil, deck: nil),
                clientNonce: UUID(),
                baseSequence: 0
            ))
            XCTFail("A cross-seat command must be rejected.")
        } catch let error as AuthoritativeGameError {
            XCTAssertEqual(error, .unauthorizedActor(expected: "north", actual: "east"))
        }
    }

    func testDuplicateNonceIsIdempotent() async throws {
        let created = try AuthoritativeGameService.create(
            .init(identities: identities, firstDealer: "north"),
            dealSeed: 99
        )
        let nonce = UUID()
        let command = AuthoritativeCommandRequest(
            state: created.state,
            sender: "north",
            actor: "north",
            action: .startDeal(dealer: nil, deck: nil),
            clientNonce: nonce,
            baseSequence: 0
        )
        let first = try await AuthoritativeGameService.apply(command)
        let duplicate = try await AuthoritativeGameService.apply(.init(
            state: first.state,
            sender: "north",
            actor: "north",
            action: .startDeal(dealer: nil, deck: nil),
            clientNonce: nonce,
            baseSequence: 0
        ))

        XCTAssertEqual(duplicate.sequence, first.sequence)
        XCTAssertEqual(
            try AuthoritativeGameService.decodeState(duplicate.state),
            try AuthoritativeGameService.decodeState(first.state)
        )

        do {
            _ = try await AuthoritativeGameService.apply(.init(
                state: first.state,
                sender: "east",
                actor: "north",
                action: .startDeal(dealer: nil, deck: nil),
                clientNonce: nonce,
                baseSequence: 0
            ))
            XCTFail("Knowing another seat's nonce must not bypass sender authorization.")
        } catch let error as AuthoritativeGameError {
            XCTAssertEqual(error, .unauthorizedActor(expected: "north", actual: "east"))
        }
    }

    func testServerRunsBotSeatsUntilAHumanMustAct() async throws {
        let profiles: [PlayerID: BotProfile] = [
            "east": .standard,
            "south": .standard,
        ]
        let created = try AuthoritativeGameService.create(
            .init(
                identities: identities,
                firstDealer: "north",
                botProfiles: profiles
            ),
            dealSeed: 123
        )
        let advanced = try await AuthoritativeGameService.apply(.init(
            state: created.state,
            sender: "north",
            actor: "north",
            action: .startDeal(dealer: nil, deck: nil),
            clientNonce: UUID(),
            baseSequence: 0
        ))
        let state = try AuthoritativeGameService.decodeState(advanced.state)

        XCTAssertGreaterThan(advanced.sequence, 1)
        let actor = try XCTUnwrap(state.snapshot.state.currentActor)
        let engine = try PreferansEngine(snapshot: state.snapshot)
        XCTAssertEqual(engine.controllingActor(of: actor), "north")
    }
}
