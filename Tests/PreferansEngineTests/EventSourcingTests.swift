import XCTest
@testable import PreferansApp
@testable import PreferansEngine

final class EventSourcingTests: XCTestCase {
    private let players: [PlayerID] = ["north", "east", "south"]

    func testHostValidatedLogStoresStructuredEventsAndReplays() async throws {
        let host = try makeHost(firstDealer: "south")
        let update = try await host.applyClientAction(
            ClientActionEnvelope(
                tableID: host.tableID,
                actor: "north",
                action: .startDeal(dealer: nil, deck: nil),
                baseHostSequence: 0
            ),
            sender: "north"
        )

        let record = try XCTUnwrap(update.validatedAction)
        XCTAssertEqual(record.sequence, 1)
        XCTAssertEqual(record.events, [
            .dealStarted(dealer: "south", activePlayers: ["north", "east", "south"])
        ])
        XCTAssertEqual(record.eventSummaries, ValidatedActionRecord.summaries(for: record.events))
        XCTAssertEqual(update.events, record.events)

        let records = await host.validatedActionLog
        let replayed = try GameLogReplayer.replay(
            players: players,
            rules: .sochi,
            firstDealer: "south",
            records: records
        )
        let snapshot = await host.currentSnapshot

        XCTAssertEqual(replayed.state, snapshot.state)
        XCTAssertEqual(replayed.score, snapshot.score)
        XCTAssertEqual(replayed.nextDealer, snapshot.nextDealer)
    }

    func testReplayerRejectsTamperedStructuredEvents() async throws {
        let host = try makeHost(firstDealer: "south")
        _ = try await host.applyClientAction(
            ClientActionEnvelope(
                tableID: host.tableID,
                actor: "north",
                action: .startDeal(dealer: nil, deck: nil),
                baseHostSequence: 0
            ),
            sender: "north"
        )

        var records = await host.validatedActionLog
        records[0].events = [
            .dealStarted(dealer: "north", activePlayers: ["east", "south", "north"])
        ]

        XCTAssertThrowsError(
            try GameLogReplayer.replay(
                players: players,
                rules: .sochi,
                firstDealer: "south",
                records: records
            )
        ) { error in
            guard case GameLogReplayError.eventMismatch(sequence: 1) = error else {
                return XCTFail("Expected eventMismatch, got \(error)")
            }
        }
    }

    func testValidatedActionRecordDecodesLegacySummariesWithoutStructuredEvents() throws {
        let record = ValidatedActionRecord(
            tableID: UUID(),
            sequence: 1,
            actor: "north",
            action: .startDeal(dealer: "south", deck: Deck.standard32),
            clientNonce: UUID(),
            baseHostSequence: 0,
            createdAt: Date(timeIntervalSince1970: 1),
            events: [.dealStarted(dealer: "south", activePlayers: ["north", "east", "south"])]
        )

        let encoded = try PreferansJSONCoder.encoder.encode(record)
        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacyObject.removeValue(forKey: "events")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)

        let decoded = try PreferansJSONCoder.decoder.decode(ValidatedActionRecord.self, from: legacyData)
        XCTAssertEqual(decoded.events, [])
        XCTAssertEqual(decoded.eventSummaries, record.eventSummaries)
    }

    func testProjectionEnvelopeCarriesStructuredEvents() throws {
        var engine = try PreferansEngine(players: players, rules: .sochi, firstDealer: "south")
        let events = try engine.startDeal(deck: Deck.standard32)
        let projection = PlayerProjectionBuilder.projection(
            for: "north",
            tableID: UUID(),
            sequence: 1,
            engine: engine,
            policy: .online
        )
        let envelope = ProjectionEnvelope(
            tableID: projection.tableID,
            sequence: projection.sequence,
            viewer: projection.viewer,
            projection: projection,
            eventSummaries: ValidatedActionRecord.summaries(for: events),
            events: events
        )

        let data = try PreferansJSONCoder.encoder.encode(envelope)
        let decoded = try PreferansJSONCoder.decoder.decode(ProjectionEnvelope.self, from: data)

        XCTAssertEqual(decoded.events, events)
        XCTAssertEqual(decoded.eventSummaries, envelope.eventSummaries)
    }

    private func makeHost(firstDealer: PlayerID) throws -> HostGameActor {
        let seats = players.map {
            PlayerIdentity(playerID: $0, gamePlayerID: $0.rawValue, displayName: $0.rawValue)
        }
        return try HostGameActor(
            hostPlayerID: "north",
            seats: seats,
            rules: .sochi,
            firstDealer: firstDealer,
            dealSource: ScriptedDealSource(decks: [Deck.standard32])
        )
    }
}
