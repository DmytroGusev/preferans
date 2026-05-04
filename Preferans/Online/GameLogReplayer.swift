import Foundation
import PreferansEngine

public enum GameLogReplayError: LocalizedError, Sendable {
    case emptyPlayers
    case sequenceGap(expected: Int, actual: Int)
    case eventMismatch(sequence: Int)
    case eventSummaryMismatch(sequence: Int)

    public var errorDescription: String? {
        switch self {
        case .emptyPlayers:
            return "Cannot replay a game log without players."
        case let .sequenceGap(expected, actual):
            return "Validated action log has a sequence gap. Expected \(expected), got \(actual)."
        case let .eventMismatch(sequence):
            return "Validated action log emitted different structured events when replayed at sequence \(sequence)."
        case let .eventSummaryMismatch(sequence):
            return "Validated action log emitted different event summaries when replayed at sequence \(sequence)."
        }
    }
}

public enum GameLogReplayer {
    /// Rebuilds an engine by replaying the host-validated action log. This
    /// works because `HostGameActor` turns every startDeal into an explicit
    /// dealer+deck action before storing it.
    ///
    /// New records carry structured events; replay verifies those facts so
    /// the append-only log is not just "commands we once accepted" but a
    /// deterministic event stream. Legacy records that only have summaries
    /// still get a weaker summary check.
    public static func replay(
        players: [PlayerID],
        rules: PreferansRules,
        firstDealer: PlayerID?,
        records: [ValidatedActionRecord]
    ) throws -> PreferansEngine {
        guard !players.isEmpty else { throw GameLogReplayError.emptyPlayers }
        var engine = try PreferansEngine(players: players, rules: rules, firstDealer: firstDealer ?? players[0])
        var expected = 1
        for record in records.sorted(by: { $0.sequence < $1.sequence }) {
            guard record.sequence == expected else {
                throw GameLogReplayError.sequenceGap(expected: expected, actual: record.sequence)
            }
            let replayedEvents = try engine.apply(record.action)
            if !record.events.isEmpty {
                guard replayedEvents == record.events else {
                    throw GameLogReplayError.eventMismatch(sequence: record.sequence)
                }
            } else if !record.eventSummaries.isEmpty {
                guard ValidatedActionRecord.summaries(for: replayedEvents) == record.eventSummaries else {
                    throw GameLogReplayError.eventSummaryMismatch(sequence: record.sequence)
                }
            }
            expected += 1
        }
        return engine
    }
}
