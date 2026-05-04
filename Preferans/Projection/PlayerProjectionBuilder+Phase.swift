import Foundation
import PreferansEngine

extension PlayerProjectionBuilder {
    static func phaseFrame(
        for viewer: PlayerID,
        engine: PreferansEngine,
        policy: ProjectionPolicy
    ) -> ProjectionBuildFrame {
        switch engine.state {
        case .waitingForDeal:
            var frame = ProjectionBuildFrame(
                phase: .waitingForDeal(nextDealer: engine.nextDealer),
                status: .readyToDeal
            )
            frame.legal.canStartDeal = true
            return frame

        case let .bidding(state):
            var frame = ProjectionBuildFrame(
                phase: .bidding(currentPlayer: state.currentPlayer, highestBid: state.highestBid),
                status: .bidding(currentPlayer: state.currentPlayer)
            )
            frame.dealer = state.dealer
            frame.activePlayers = state.activePlayers
            frame.hands = state.hands
            frame.talonCards = state.talon
            frame.auction = state.calls
            frame.currentActor = state.currentPlayer
            frame.legal.bidCalls = engine.legalBidCalls(for: viewer)
            markActiveRoles(frame.activePlayers, into: &frame.roleMap)
            return frame

        case let .awaitingDiscard(state):
            var frame = ProjectionBuildFrame(
                phase: .awaitingDiscard(declarer: state.declarer, finalBid: state.finalBid),
                status: .takingPrikup(declarer: state.declarer)
            )
            frame.dealer = state.dealer
            frame.activePlayers = state.activePlayers
            frame.hands = state.hands
            frame.talonCards = state.talon
            frame.auction = state.auction
            frame.currentActor = state.declarer
            frame.roleMap[state.declarer] = .declarer
            frame.legal.canDiscard = viewer == state.declarer
            markActiveRoles(frame.activePlayers, into: &frame.roleMap)
            return frame

        case let .awaitingContract(state):
            var frame = ProjectionBuildFrame(
                phase: .awaitingContract(declarer: state.declarer, finalBid: state.finalBid),
                status: .namingContract(declarer: state.declarer, pickingTotusStrain: state.finalBid == .totus)
            )
            frame.dealer = state.dealer
            frame.activePlayers = state.activePlayers
            frame.hands = state.hands
            frame.talonCards = state.talon
            frame.discardCards = state.discard
            frame.auction = state.auction
            frame.currentActor = state.declarer
            frame.roleMap[state.declarer] = .declarer
            frame.legal.contractOptions = viewer == state.declarer ? engine.legalContractDeclarations(for: viewer) : []
            markActiveRoles(frame.activePlayers, into: &frame.roleMap)
            return frame

        case let .awaitingWhist(state):
            var frame = ProjectionBuildFrame(
                phase: .awaitingWhist(
                    currentPlayer: state.currentPlayer,
                    declarer: state.declarer,
                    contract: state.contract
                ),
                status: .callingWhist(currentPlayer: state.currentPlayer)
            )
            frame.dealer = state.dealer
            frame.activePlayers = state.activePlayers
            frame.hands = state.hands
            frame.talonCards = state.talon
            frame.discardCards = state.discard
            frame.whistCalls = state.calls
            frame.currentActor = state.currentPlayer
            frame.roleMap[state.declarer] = .declarer
            for defender in state.defenders { frame.roleMap[defender] = .defender }
            frame.legal.whistCalls = engine.legalWhistCalls(for: viewer)
            markActiveRoles(frame.activePlayers, into: &frame.roleMap)
            return frame

        case let .awaitingDefenderMode(state):
            var frame = ProjectionBuildFrame(
                phase: .awaitingDefenderMode(whister: state.whister, contract: state.contract),
                status: .choosingDefenderMode(whister: state.whister)
            )
            frame.dealer = state.dealer
            frame.activePlayers = state.activePlayers
            frame.hands = state.hands
            frame.talonCards = state.talon
            frame.discardCards = state.discard
            frame.whistCalls = state.whistCalls
            frame.currentActor = state.whister
            frame.roleMap[state.declarer] = .declarer
            for defender in state.defenders {
                frame.roleMap[defender] = defender == state.whister ? .whister : .defender
            }
            frame.legal.defenderModes = viewer == state.whister ? [.closed, .open] : []
            markActiveRoles(frame.activePlayers, into: &frame.roleMap)
            return frame

        case let .playing(state):
            return playingFrame(for: viewer, engine: engine, state: state, policy: policy)

        case let .dealFinished(result):
            var frame = ProjectionBuildFrame(
                phase: .dealFinished(result: result),
                status: .dealScored
            )
            frame.activePlayers = result.activePlayers
            frame.completedTrickCount = result.completedTricks.count
            frame.trickCounts = result.trickCounts
            frame.legal.canStartDeal = true
            markActiveRoles(frame.activePlayers, into: &frame.roleMap)
            return frame

        case let .gameOver(summary):
            var frame = ProjectionBuildFrame(
                phase: .gameOver(summary: summary),
                status: .matchOver(winner: summary.standings.first?.player)
            )
            frame.activePlayers = summary.lastDeal.activePlayers
            frame.completedTrickCount = summary.lastDeal.completedTricks.count
            frame.trickCounts = summary.lastDeal.trickCounts
            markActiveRoles(frame.activePlayers, into: &frame.roleMap)
            return frame
        }
    }

    private static func playingFrame(
        for viewer: PlayerID,
        engine: PreferansEngine,
        state: PlayingState,
        policy: ProjectionPolicy
    ) -> ProjectionBuildFrame {
        var frame = ProjectionBuildFrame(
            phase: .playing(
                currentPlayer: state.currentPlayer,
                leader: state.leader,
                kind: projectedPlayKind(for: state.kind)
            ),
            status: playingStatus(for: state, currentActor: engine.state.currentActor)
        )
        frame.dealer = state.dealer
        frame.activePlayers = state.activePlayers
        frame.hands = state.hands
        frame.talonCards = state.talon
        frame.discardCards = state.discard
        frame.currentActor = engine.state.currentActor
        frame.currentTrick = state.currentTrick
        frame.completedTrickCount = state.completedTricks.count
        frame.trickCounts = state.trickCounts
        frame.legal.playableCards = engine.legalCards(for: viewer)
        frame.legal.settlementOptions = engine.legalSettlements(for: viewer)
        frame.legal.pendingSettlement = state.pendingSettlement
        frame.legal.canAcceptSettlement = engine.canAcceptSettlement(player: viewer)
        frame.legal.canRejectSettlement = engine.canRejectSettlement(player: viewer)
        applyPlayRolesAndVisibility(state.kind, activePlayers: frame.activePlayers, policy: policy, to: &frame)
        markActiveRoles(frame.activePlayers, into: &frame.roleMap)
        return frame
    }

    private static func projectedPlayKind(for kind: PlayKind) -> ProjectedPlayKind {
        switch kind {
        case let .game(context):
            return .game(
                declarer: context.declarer,
                contract: context.contract,
                defenders: context.defenders,
                whisters: context.whisters,
                defenderPlayMode: context.defenderPlayMode
            )
        case let .misere(context):
            return .misere(declarer: context.declarer)
        case .allPass:
            return .allPass
        }
    }

    private static func playingStatus(for state: PlayingState, currentActor: PlayerID?) -> ProjectedStatus {
        if let proposal = state.pendingSettlement {
            return .settling(
                proposer: proposal.proposer,
                target: proposal.settlement.target,
                targetTricks: proposal.settlement.targetTricks,
                currentPlayer: currentActor
            )
        }

        return .playingTrick(
            currentPlayer: state.currentPlayer,
            trickNumber: state.completedTricks.count + 1
        )
    }

    private static func applyPlayRolesAndVisibility(
        _ kind: PlayKind,
        activePlayers: [PlayerID],
        policy: ProjectionPolicy,
        to frame: inout ProjectionBuildFrame
    ) {
        switch kind {
        case let .game(context):
            frame.roleMap[context.declarer] = .declarer
            for defender in context.defenders {
                frame.roleMap[defender] = context.whisters.contains(defender) ? .whister : .defender
            }
            if context.defenderPlayMode == .open && policy.revealOpenDefenderHandsToAll {
                frame.revealHandOwners.formUnion(context.defenders)
            }
            frame.whistCalls = context.whistCalls

        case let .misere(context):
            frame.roleMap[context.declarer] = .declarer
            let defenders = activePlayers.filter { $0 != context.declarer }
            for defender in defenders { frame.roleMap[defender] = .whister }
            frame.revealHandOwners.formUnion(activePlayers)

        case .allPass:
            break
        }
    }

    private static func markActiveRoles(_ players: [PlayerID], into roleMap: inout [PlayerID: SeatRole]) {
        for player in players where roleMap[player] == nil {
            roleMap[player] = .active
        }
    }
}
