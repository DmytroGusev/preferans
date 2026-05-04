import XCTest
@testable import PreferansApp
@testable import PreferansEngine

final class WireCompatibilityTests: XCTestCase {
    private let tableID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
    private let nonce = UUID(uuidString: "00000000-0000-0000-0000-000000000456")!
    private let date = Date(timeIntervalSince1970: 1_714_000_000)
    private let players: [PlayerID] = ["north", "east", "south"]

    func testEveryWireMessageRoundTripsThroughSharedJSONCoder() throws {
        let projection = try makeProjection(sequence: 1)
        let messages: [GameWireMessage] = [
            .hello(HelloEnvelope(tableID: tableID, player: seats()[0], lastSeenSequence: 1)),
            .seatAssignment(SeatAssignmentEnvelope(tableID: tableID, hostPlayerID: "north", seats: seats(), rules: .sochi)),
            .clientAction(ClientActionEnvelope(
                tableID: tableID,
                actor: "north",
                action: .bid(player: "north", call: .pass),
                clientNonce: nonce,
                baseHostSequence: 1,
                sentAt: date
            )),
            .projection(ProjectionEnvelope(
                tableID: tableID,
                sequence: 1,
                viewer: "north",
                projection: projection,
                eventSummaries: ["north passed"],
                events: [.bidAccepted(AuctionCall(player: "north", call: .pass))]
            )),
            .hostError(HostErrorEnvelope(
                tableID: tableID,
                sequence: 1,
                recipient: "north",
                clientNonce: nonce,
                message: "Rejected"
            )),
            .resyncRequest(ResyncRequestEnvelope(tableID: tableID, requester: "east", lastSeenSequence: 1)),
            .ping(PingEnvelope(tableID: tableID, sentAt: date))
        ]

        for message in messages {
            let data = try PreferansJSONCoder.encoder.encode(message)
            let decoded = try PreferansJSONCoder.decoder.decode(GameWireMessage.self, from: data)
            XCTAssertEqual(decoded, message)
        }
    }

    func testLegacyProjectionEnvelopeDecodesWithDefaultSchemaAndEmptyEvents() throws {
        let projection = try makeProjection(sequence: 2)
        let envelope = ProjectionEnvelope(
            tableID: tableID,
            sequence: 2,
            viewer: "north",
            projection: projection,
            eventSummaries: ["legacy summary"],
            events: [.dealStarted(dealer: "south", activePlayers: players)]
        )
        let encoded = try PreferansJSONCoder.encoder.encode(envelope)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "schemaVersion")
        legacy.removeValue(forKey: "eventSummaries")
        legacy.removeValue(forKey: "events")

        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let decoded = try PreferansJSONCoder.decoder.decode(ProjectionEnvelope.self, from: legacyData)

        XCTAssertEqual(decoded.schemaVersion, AppIdentifiers.gameWireSchemaVersion)
        XCTAssertEqual(decoded.tableID, envelope.tableID)
        XCTAssertEqual(decoded.sequence, envelope.sequence)
        XCTAssertEqual(decoded.viewer, envelope.viewer)
        XCTAssertEqual(decoded.eventSummaries, [])
        XCTAssertEqual(decoded.events, [])
    }

    func testPersistencePayloadsRoundTripThroughSharedJSONCoder() throws {
        var engine = try PreferansEngine(players: players, rules: .sochi, firstDealer: "south")
        _ = try engine.startDeal(deck: Deck.standard32)
        let result = try finishPlayedSixSpades(engine: &engine)

        let summary = CloudTableSummary(
            tableID: tableID,
            status: .playing,
            hostPlayerID: "north",
            seats: seats(),
            rules: .sochi,
            lastSequence: 3,
            createdAt: date,
            updatedAt: date,
            shareURL: URL(string: "https://example.test/table")
        )
        let appSnapshot = AppEngineSnapshot(engine: engine)
        let completedDeal = CompletedDealArchive(
            tableID: tableID,
            sequence: 3,
            result: result,
            cumulativeScore: engine.score,
            completedAt: date
        )

        try assertRoundTrip(summary)
        try assertRoundTrip(appSnapshot)
        try assertRoundTrip(completedDeal)
    }

    private func makeProjection(sequence: Int) throws -> PlayerGameProjection {
        var engine = try PreferansEngine(players: players, rules: .sochi, firstDealer: "south")
        _ = try engine.startDeal(deck: Deck.standard32)
        return PlayerProjectionBuilder.projection(
            for: "north",
            tableID: tableID,
            sequence: sequence,
            engine: engine,
            identities: seats(),
            policy: .online
        )
    }

    private func finishPlayedSixSpades(engine: inout PreferansEngine) throws -> DealResult {
        try EngineTestDriver.driveAuctionWinning(
            engine: &engine,
            declarer: "north",
            bid: .game(GameContract(6, .suit(.spades)))
        )
        try EngineTestDriver.discardTalon(engine: &engine, declarer: "north")
        try EngineTestDriver.declareContract(engine: &engine, declarer: "north", contract: GameContract(6, .suit(.spades)))
        try EngineTestDriver.forceWhist(engine: &engine)
        try EngineTestDriver.playOut(
            engine: &engine,
            policy: .declarerHighestDefendersLowest(declarer: "north")
        )
        guard case let .dealFinished(result) = engine.state else {
            throw EngineTestError("Expected dealFinished, got \(engine.state.description).")
        }
        return result
    }

    private func seats() -> [PlayerIdentity] {
        players.map {
            PlayerIdentity(playerID: $0, gamePlayerID: $0.rawValue, displayName: $0.rawValue.capitalized)
        }
    }

    private func assertRoundTrip<T: Codable & Equatable>(
        _ value: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let data = try PreferansJSONCoder.encoder.encode(value)
        let decoded = try PreferansJSONCoder.decoder.decode(T.self, from: data)
        XCTAssertEqual(decoded, value, file: file, line: line)
    }
}
