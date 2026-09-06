import Foundation

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
        if revealAll { return reveal(talon, when: true) }
        if case .awaitingDiscard = state { return reveal(talon, when: true) }
        guard case let .playing(playing) = state,
              playing.usesTalonLeads,
              playing.completedTricks.count < 2 else {
            return reveal(talon, when: false)
        }
        // Raspasy opens the talon one card at a time. Keep the second card
        // hidden throughout the first opening trick; after it closes, reveal
        // the second lead while retaining the first as public history.
        return talon.enumerated().map { index, card in
            index <= playing.completedTricks.count ? .known(card) : .hidden
        }
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
