import Foundation
import PreferansEngine

public enum GameLogReplayError: LocalizedError, Sendable {
    case emptyPlayers
    case sequenceGap(expected: Int, actual: Int)

    public var errorDescription: String? {
        switch self {
        case .emptyPlayers:
            return "Cannot replay a game log without players."
        case let .sequenceGap(expected, actual):
            return "Validated action log has a sequence gap. Expected \(expected), got \(actual)."
        }
    }
}

public enum GameLogReplayer {
    /// Rebuilds an engine by replaying the host-validated action log. This works because HostGameActor
    /// turns every startDeal into an explicit dealer+deck action before storing it.
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
            _ = try engine.apply(record.action.action)
            expected += 1
        }
        return engine
    }
}
