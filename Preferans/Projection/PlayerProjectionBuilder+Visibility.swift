import Foundation
import PreferansEngine

extension PlayerProjectionBuilder {
    static func seatProjections(
        for players: [PlayerID],
        viewer: PlayerID,
        identityMap: [PlayerID: String],
        frame: ProjectionBuildFrame,
        policy: ProjectionPolicy
    ) -> [SeatProjection] {
        players.map { player in
            let cards = frame.hands[player] ?? []
            let isActive = frame.activePlayers.isEmpty ? true : frame.activePlayers.contains(player)
            let isDealer = frame.dealer == player
            let role = frame.roleMap[player] ?? (isActive ? SeatRole.active : .sittingOut)

            return SeatProjection(
                player: player,
                displayName: identityMap[player] ?? player.rawValue,
                isActive: isActive,
                isDealer: isDealer,
                isCurrentActor: frame.currentActor == player,
                role: role,
                hand: projectedHand(cards, owner: player, viewer: viewer, frame: frame, policy: policy),
                trickCount: frame.trickCounts[player] ?? 0
            )
        }
    }

    static func projectTalon(_ talon: [Card], state: DealState, viewer: PlayerID, revealAll: Bool) -> [ProjectedCard] {
        // The prikup is opened publicly during the talon exchange. In
        // lead-suit all-pass play the talon also remains public because it
        // determines the suit everyone must follow on the first two tricks.
        reveal(talon, when: revealAll || state.hasPublicTalon)
    }

    static func projectDiscard(
        _ discard: [Card],
        state: DealState,
        viewer: PlayerID,
        revealAll: Bool,
        revealDeclarerDiscardToDeclarer: Bool
    ) -> [ProjectedCard] {
        guard !discard.isEmpty else { return [] }
        let isDeclarerViewer = revealDeclarerDiscardToDeclarer && state.declarer == viewer
        return reveal(discard, when: revealAll || isDeclarerViewer)
    }

    private static func projectedHand(
        _ cards: [Card],
        owner: PlayerID,
        viewer: PlayerID,
        frame: ProjectionBuildFrame,
        policy: ProjectionPolicy
    ) -> [ProjectedCard] {
        let shouldReveal = policy.revealAllHands || owner == viewer || frame.revealHandOwners.contains(owner)
        return reveal(cards, when: shouldReveal)
    }

    private static func reveal(_ cards: [Card], when shouldReveal: Bool) -> [ProjectedCard] {
        if shouldReveal { return cards.sorted().map(ProjectedCard.known) }
        return Array(repeating: .hidden, count: cards.count)
    }
}

private extension DealState {
    var hasPublicTalon: Bool {
        switch self {
        case .awaitingDiscard:
            return true
        case let .playing(state):
            guard case let .allPass(context) = state.kind,
                  context.talonPolicy == .leadSuitOnly else {
                return false
            }
            return state.completedTricks.count < 2
        default:
            return false
        }
    }
}
