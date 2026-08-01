import Foundation
import PreferansEngine

/// Shared presentation policy for the beat between authoritative card play
/// and the table sweeping a completed trick.
enum AdvancePresentation {
    /// Build a hold from the exact viewer projection that preceded the closing
    /// card. Using that projection preserves open-hand visibility, actor state,
    /// trick numbering, and public talon knowledge without reconstructing any
    /// of them from the scored result.
    static func completedTrickHold(
        events: [PreferansEvent],
        viewer: PlayerID,
        preProjection: PlayerGameProjection,
        visibleTalonBeforeAction: [ProjectedCard]
    ) -> PendingAdvance? {
        guard let trick = events.lazy.compactMap({ event -> Trick? in
            if case let .trickCompleted(trick) = event { return trick }
            return nil
        }).first else { return nil }

        return PendingAdvance(
            waitingOn: viewer,
            trickPlays: trick.tablePlays,
            trickWinner: trick.winner,
            talonOverride: trick.talonLead == nil ? nil : visibleTalonBeforeAction,
            phaseOverride: preProjection.phase,
            completedTrickCountOverride: preProjection.completedTrickCount
        )
    }
}

extension PlayerGameProjection {
    /// Presentation-only freeze used by both local tap-to-advance and online
    /// timed trick holds. The engine/host sequence has already advanced; this
    /// method only keeps the just-finished public beat visible for the viewer.
    public func applyingAdvanceFreeze(_ advance: PendingAdvance?) -> PlayerGameProjection {
        var p = self
        guard let advance else { return p }
        if let plays = advance.trickPlays {
            p.currentTrick = plays
        }
        if let winner = advance.trickWinner {
            // Roll the winner's count back to its pre-close value so the tally
            // on the felt matches the still-visible trick.
            let prev = p.trickCounts[winner] ?? 0
            p.trickCounts[winner] = max(0, prev - 1)
            if let i = p.seats.firstIndex(where: { $0.player == winner }) {
                p.seats[i].trickCount = max(0, p.seats[i].trickCount - 1)
            }
        }
        if let talon = advance.talonOverride {
            p.talon = talon
        }
        if let count = advance.completedTrickCountOverride {
            p.completedTrickCount = count
        }
        if let phase = advance.phaseOverride {
            p.phase = phase
        }
        // While the hold is up, suppress legal-action affordances so the next
        // actor cannot skip past the visible trick result.
        p.legal.playableCards = []
        p.legal.playableCardsOwner = nil
        p.legal.settlementOptions = []
        p.legal.canAcceptSettlement = false
        p.legal.canRejectSettlement = false
        p.legal.canStartDeal = false
        return p
    }
}

/// Pause descriptor shared by local tap-to-advance and online timed holds.
/// When non-nil, the rendered table stays on a completed public beat while the
/// authoritative engine or host projection remains fully advanced.
public struct PendingAdvance: Equatable, Sendable {
    /// Seat whose on-screen table is holding the beat.
    public let waitingOn: PlayerID
    /// When set, render these plays as the current trick on the felt.
    public let trickPlays: [CardPlay]?
    /// Seat that just won the trick, used to roll its displayed count back.
    public let trickWinner: PlayerID?
    /// Exact public talon state from immediately before the trick closed.
    public let talonOverride: [ProjectedCard]?
    /// Exact phase that preceded the authoritative transition.
    public let phaseOverride: ProjectedPhase?
    /// Completed-trick count to display while the beat is held.
    public let completedTrickCountOverride: Int?

    public init(
        waitingOn: PlayerID,
        trickPlays: [CardPlay]?,
        trickWinner: PlayerID?,
        talonOverride: [ProjectedCard]? = nil,
        phaseOverride: ProjectedPhase?,
        completedTrickCountOverride: Int?
    ) {
        self.waitingOn = waitingOn
        self.trickPlays = trickPlays
        self.trickWinner = trickWinner
        self.talonOverride = talonOverride
        self.phaseOverride = phaseOverride
        self.completedTrickCountOverride = completedTrickCountOverride
    }
}
