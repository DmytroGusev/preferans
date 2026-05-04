import Foundation

extension PreferansEngine {
    func reduceProposeSettlement(
        player: PlayerID,
        settlement: TrickSettlement
    ) throws -> EngineTransition {
        guard case var .playing(playing) = state else {
            throw PreferansError.invalidState(expected: "playing", actual: state.description)
        }
        guard playing.pendingSettlement == nil else {
            throw PreferansError.illegalSettlement("A settlement proposal is already pending.")
        }
        guard playing.currentTrick.isEmpty else {
            throw PreferansError.illegalSettlement("Settlements can only be offered between tricks.")
        }
        guard playing.activePlayers.contains(player) else {
            throw PreferansError.invalidPlayer(player)
        }
        try validateSettlement(settlement, in: playing)

        let proposal = TrickSettlementProposal(
            proposer: player,
            settlement: settlement,
            acceptedBy: [player]
        )
        playing.pendingSettlement = proposal
        return EngineTransition(state: .playing(playing), events: [.settlementProposed(proposal)])
    }

    mutating func reduceAcceptSettlement(player: PlayerID) throws -> EngineTransition {
        guard case var .playing(playing) = state else {
            throw PreferansError.invalidState(expected: "playing", actual: state.description)
        }
        guard var proposal = playing.pendingSettlement else {
            throw PreferansError.illegalSettlement("There is no settlement proposal to accept.")
        }
        guard playing.activePlayers.contains(player) else {
            throw PreferansError.invalidPlayer(player)
        }
        guard !proposal.acceptedBy.contains(player) else {
            throw PreferansError.illegalSettlement("\(player) already accepted this settlement.")
        }

        proposal.acceptedBy.insert(player)
        var events: [PreferansEvent] = [.settlementAccepted(player: player)]
        if proposal.acceptedBy.isSuperset(of: Set(playing.activePlayers)) {
            playing.pendingSettlement = nil
            let result = try scoreSettlement(proposal.settlement, in: playing)
            events.append(.playSettled(proposal.settlement))
            let transition = finalize(result)
            return EngineTransition(state: transition.state, events: events + transition.events)
        }

        playing.pendingSettlement = proposal
        return EngineTransition(state: .playing(playing), events: events)
    }

    func reduceRejectSettlement(player: PlayerID) throws -> EngineTransition {
        guard case var .playing(playing) = state else {
            throw PreferansError.invalidState(expected: "playing", actual: state.description)
        }
        guard playing.pendingSettlement != nil else {
            throw PreferansError.illegalSettlement("There is no settlement proposal to reject.")
        }
        guard playing.activePlayers.contains(player) else {
            throw PreferansError.invalidPlayer(player)
        }

        playing.pendingSettlement = nil
        return EngineTransition(state: .playing(playing), events: [.settlementRejected(player: player)])
    }
}
