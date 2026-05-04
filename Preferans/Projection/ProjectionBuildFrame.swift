import Foundation
import PreferansEngine

struct ProjectionBuildFrame {
    var dealer: PlayerID?
    var activePlayers: [PlayerID]
    var hands: [PlayerID: [Card]]
    var talonCards: [Card]
    var discardCards: [Card]
    var auction: [AuctionCall]
    var whistCalls: [WhistCallRecord]
    var currentTrick: [CardPlay]
    var completedTrickCount: Int
    var trickCounts: [PlayerID: Int]
    var currentActor: PlayerID?
    var roleMap: [PlayerID: SeatRole]
    var phase: ProjectedPhase
    var legal: LegalActionProjection
    var status: ProjectedStatus
    var revealHandOwners: Set<PlayerID>

    init(phase: ProjectedPhase, status: ProjectedStatus) {
        self.dealer = nil
        self.activePlayers = []
        self.hands = [:]
        self.talonCards = []
        self.discardCards = []
        self.auction = []
        self.whistCalls = []
        self.currentTrick = []
        self.completedTrickCount = 0
        self.trickCounts = [:]
        self.currentActor = nil
        self.roleMap = [:]
        self.phase = phase
        self.legal = LegalActionProjection()
        self.status = status
        self.revealHandOwners = []
    }
}
