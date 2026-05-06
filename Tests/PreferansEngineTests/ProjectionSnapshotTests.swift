import Foundation
import SnapshotTesting
import Testing
@testable import PreferansApp
@testable import PreferansEngine

/// Structural baselines for `PlayerGameProjection` at canonical engine
/// states. Catches regressions to the projection shape — visibility,
/// legal-action gating, role badges, talon/discard reveal — that the
/// existing predicate-based `ProjectionTests` only spot-check.
///
/// Runs on macOS via `swift test` (no iOS dependency). The view-level
/// pixel snapshots that pair with these belong in a follow-up iOS unit
/// test target; the projection is the source of truth for what those
/// views render, so locking it down here is the higher-leverage win.
@Suite("Projection snapshots", .snapshots(record: .missing))
struct ProjectionSnapshotTests {
    private static let tableID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    private let players: [PlayerID] = ["north", "east", "south"]

    @Test func biddingFreshDeal_northViewer() throws {
        let engine = try makeFreshDealEngine()
        try assertProjection(engine: engine, viewer: "north")
    }

    @Test func biddingFreshDeal_eastViewer_handsHidden() throws {
        let engine = try makeFreshDealEngine()
        try assertProjection(engine: engine, viewer: "east")
    }

    @Test func awaitingDiscard_declarerSeesTalon() throws {
        let engine = try makeAwaitingDiscardEngine()
        try assertProjection(engine: engine, viewer: "north")
    }

    @Test func awaitingDiscard_defenderAlsoSeesTalonDuringExchange() throws {
        let engine = try makeAwaitingDiscardEngine()
        try assertProjection(engine: engine, viewer: "east")
    }

    @Test func midTrickPlay_declarerView() throws {
        let engine = try makeMidTrickEngine()
        try assertProjection(engine: engine, viewer: "north")
    }

    @Test func midTrickPlay_defenderViewHidesDeclarerHand() throws {
        let engine = try makeMidTrickEngine()
        try assertProjection(engine: engine, viewer: "east")
    }

    private func assertProjection(
        engine: PreferansEngine,
        viewer: PlayerID,
        fileID: StaticString = #fileID,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        let projection = PlayerProjectionBuilder.projection(
            for: viewer,
            tableID: Self.tableID,
            sequence: 0,
            engine: engine,
            policy: .online
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(projection)
        // `[PlayerID: Int]` Codable encoding emits an alternating
        // [key, value, ...] array whose order tracks Dictionary iteration —
        // non-deterministic per run. Walk the JSON and sort those pairs by
        // their `rawValue` key so the snapshot is stable.
        let normalized = try normalizeAlternatingKeyValueArrays(data: data)
        let json = String(decoding: normalized, as: UTF8.self)
        assertSnapshot(
            of: json,
            as: .lines,
            // Disambiguate per-viewer baselines so two viewers of the same
            // state get separate files instead of overwriting one another.
            named: viewer.rawValue,
            fileID: fileID,
            file: file,
            testName: testName,
            line: line,
            column: column
        )
    }

    // MARK: - JSON normalization

    /// Walk a parsed JSON tree and stable-sort any array that looks like
    /// `[{"rawValue": "..."}, scalar, ...]`. That's how `Codable` encodes
    /// `[PlayerID: Int]` dicts; without this pass the snapshot output is
    /// reordered on every Dictionary iteration.
    private func normalizeAlternatingKeyValueArrays(data: Data) throws -> Data {
        let decoded = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let normalized = normalize(decoded)
        return try JSONSerialization.data(
            withJSONObject: normalized,
            options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
        )
    }

    private func normalize(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            return dict.mapValues(normalize)
        }
        if let array = value as? [Any] {
            let mapped = array.map(normalize)
            if let pairs = playerKeyedPairs(from: mapped) {
                return pairs.sorted { lhs, rhs in
                    keyString(of: lhs.0) < keyString(of: rhs.0)
                }.flatMap { [$0.0, $0.1] }
            }
            return mapped
        }
        return value
    }

    /// Returns `(key, value)` pairs if the array's even-indexed entries
    /// are all `{"rawValue": "..."}` boxes (a `PlayerID`-style key).
    /// Otherwise returns `nil` — leave the array's order alone.
    private func playerKeyedPairs(from array: [Any]) -> [(Any, Any)]? {
        guard array.count >= 2, array.count.isMultiple(of: 2) else { return nil }
        var pairs: [(Any, Any)] = []
        for i in stride(from: 0, to: array.count, by: 2) {
            guard let dict = array[i] as? [String: Any],
                  dict.count == 1,
                  dict["rawValue"] is String else {
                return nil
            }
            pairs.append((array[i], array[i + 1]))
        }
        return pairs
    }

    private func keyString(of value: Any) -> String {
        if let dict = value as? [String: Any], let s = dict["rawValue"] as? String {
            return s
        }
        return ""
    }

    // MARK: - Engine fixtures

    private func makeFreshDealEngine() throws -> PreferansEngine {
        var engine = try PreferansEngine(players: players, rules: .sochi, firstDealer: "south")
        _ = try engine.apply(.startDeal(dealer: "south", deck: Deck.standard32))
        return engine
    }

    private func makeAwaitingDiscardEngine() throws -> PreferansEngine {
        var engine = try makeFreshDealEngine()
        try EngineTestDriver.driveAuctionWinning(
            engine: &engine,
            declarer: "north",
            bid: .game(GameContract(6, .suit(.spades)))
        )
        return engine
    }

    private func makeMidTrickEngine() throws -> PreferansEngine {
        var engine = try makeAwaitingDiscardEngine()
        guard case let .awaitingDiscard(exchange) = engine.state else {
            throw EngineTestError("Expected awaitingDiscard fixture; got \(engine.state.description).")
        }
        _ = try engine.apply(.discard(player: "north", cards: exchange.talon))
        try EngineTestDriver.declareContract(engine: &engine, declarer: "north", contract: GameContract(6, .suit(.spades)))
        try EngineTestDriver.forceWhist(engine: &engine)
        guard case let .playing(playing) = engine.state else {
            throw EngineTestError("Expected playing state; got \(engine.state.description).")
        }
        let firstCard = try #require(engine.legalCards(for: playing.currentPlayer).min())
        _ = try engine.apply(.playCard(player: playing.currentPlayer, card: firstCard))
        return engine
    }
}
