import Foundation

extension PreferansEngine {
    mutating func reducePlayCard(player: PlayerID, card: Card) throws -> EngineTransition {
        guard case var .playing(playing) = state else {
            throw PreferansError.invalidState(expected: "playing", actual: state.description)
        }
        guard playing.pendingSettlement == nil else {
            throw PreferansError.illegalSettlement("A settlement proposal is awaiting responses.")
        }
        try validateCurrent(player, expected: playing.currentPlayer)
        guard let cardIndex = playing.hands[player]?.firstIndex(of: card) else {
            throw PreferansError.cardNotInHand(player: player, card: card)
        }
        guard isLegal(card: card, by: player, in: playing) else {
            throw PreferansError.illegalCardPlay("\(card) is not legal for \(player).")
        }

        playing.hands[player]?.remove(at: cardIndex)
        let play = CardPlay(player: player, card: card)
        playing.currentTrick.append(play)
        var events: [PreferansEvent] = [.cardPlayed(play)]

        if playing.currentTrick.count < playing.activePlayers.count {
            playing.currentPlayer = playing.activePlayers.cyclicNext(after: player)
            return EngineTransition(state: .playing(playing), events: events)
        }

        let trick = completeCurrentTrick(in: &playing)
        events.append(.trickCompleted(trick))

        if playing.isComplete {
            let result = scoreCompletedPlay(playing)
            let transition = finalize(result)
            return EngineTransition(state: transition.state, events: events + transition.events)
        }

        return EngineTransition(state: .playing(playing), events: events)
    }
}
