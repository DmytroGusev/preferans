import Foundation
import PreferansEngine

/// Pure projection from authoritative engine state into the small metadata
/// record persisted by the room worker. Keeping this outside the coordinator
/// prevents transport scheduling from owning score interpretation as well.
struct RoomStateReportBuilder {
    static func summary(
        variantTag: String?,
        sequence: Int,
        dealNumber: Int,
        state: DealState
    ) -> OnlineStateSummary {
        OnlineStateSummary(
            variant: variantTag,
            lastSequence: sequence,
            phase: phaseLabel(for: state),
            dealNumber: dealNumber,
            result: finishedResult(from: state)
        )
    }

    /// Coarse, lobby-facing phase label for a deal state.
    static func phaseLabel(for state: DealState) -> String {
        switch state {
        case .waitingForDeal:       return "waiting"
        case .bidding:              return "bidding"
        case .awaitingDiscard:      return "exchange"
        case .awaitingContract:     return "declaring"
        case .awaitingWhist:        return "whist"
        case .awaitingDefenderMode: return "defending"
        case .playing:              return "playing"
        case .dealFinished:         return "scoring"
        case .gameOver:             return "finished"
        }
    }

    /// Persist the same winner and zero-sum balances shown by the in-app final
    /// standings. Stable seat order does not choose a winner when balances tie.
    static func finishedResult(from state: DealState) -> OnlineGameResult? {
        guard case let .gameOver(summary) = state else { return nil }
        let balances = Dictionary(uniqueKeysWithValues: summary.standings.map {
            ($0.player.rawValue, $0.balance)
        })
        return OnlineGameResult(
            winner: summary.soleWinner,
            finalBalances: balances
        )
    }
}
