import Foundation

/// The only event boundary for online clients. Keep this switch exhaustive:
/// adding a domain event requires an explicit visibility decision.
public enum OnlineEventProjection {
    public static func events(_ events: [PreferansEvent], for viewer: PlayerID) -> [PreferansEvent] {
        events.map { event in
            switch event {
            case let .talonExchanged(declarer, talon, discard):
                // The exchange itself is public; the discarded cards are not.
                return .talonExchanged(
                    declarer: declarer,
                    talon: viewer == declarer ? talon : [],
                    discard: viewer == declarer ? discard : []
                )
            case .dealStarted, .bidAccepted, .auctionWon, .allPassed,
                 .contractDeclared, .contractConcededWithoutThree, .whistAccepted,
                 .defenderModeChosen, .playStarted, .cardPlayed, .trickCompleted,
                 .settlementProposed, .settlementAccepted, .settlementRejected,
                 .playSettled, .dealScored, .matchEnded:
                // Completed deals intentionally reveal their initial hands for review.
                return event
            }
        }
    }
}
