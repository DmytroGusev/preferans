import Foundation

struct SnapshotBid: Codable {
    let playerID: UUID
    let contract: Contract
}

struct SnapshotTrickPlay: Codable {
    let playerID: UUID
    let card: Card
}

struct SnapshotWhistDecision: Codable {
    let playerID: UUID
    let decision: WhistDecision
}

struct SnapshotOpenHand: Codable {
    let playerID: UUID
}

struct SnapshotPassedBidder: Codable {
    let playerID: UUID
}

struct SnapshotClaimResponse: Codable {
    let playerID: UUID
    let response: ClaimResponse
}

struct SnapshotClaimProposal: Codable {
    let proposerID: UUID
    let targetPlayerID: UUID
    let claimedTotalTricks: Int
    let responses: [SnapshotClaimResponse]
}

struct SnapshotWhistLedgerEntry: Codable {
    let writerID: UUID
    let targetID: UUID
    let amount: Int
}

struct MultiplayerGameState: Codable {
    let screen: GameScreen
    let playerCount: Int
    let ruleSet: PreferansRuleSet
    let players: [Player]
    let dealerSeat: Int
    let phase: Phase
    let talon: [Card]
    let hiddenDiscard: [Card]
    let selectedDiscardIDs: [String]
    let bids: [SnapshotBid]
    let currentBid: SnapshotBid?
    let declaredContract: Contract?
    let declarerID: UUID?
    let passedBidderIDs: [SnapshotPassedBidder]
    let auctionSummary: String?
    let whistDecisions: [SnapshotWhistDecision]
    let lightWhistControllerID: UUID?
    let openHandPlayerIDs: [SnapshotOpenHand]
    let activeTrick: [SnapshotTrickPlay]
    let trickHistory: [[SnapshotTrickPlay]]
    let currentTurnSeat: Int
    let handSummary: String?
    let partySummary: String?
    let partyBreakdown: [String]
    let trickClaimProposal: SnapshotClaimProposal?
    let whistLedger: [SnapshotWhistLedgerEntry]
}

struct MultiplayerGameSnapshot: Codable {
    let roomID: String
    let revision: Int
    let updatedByPlayerID: String
    let updatedAt: Date
    let state: MultiplayerGameState
}

enum MultiplayerGameAction: Codable {
    case roomUpdated
    case startHand
    case resetToLobby
    case nextHand
    case bid(playerID: UUID, contract: Contract)
    case passBid(playerID: UUID)
    case takeTalon(playerID: UUID)
    case discard(playerID: UUID, cardIDs: [String])
    case declareContract(playerID: UUID, contract: Contract)
    case whist(playerID: UUID, decision: WhistDecision)
    case playCard(playerID: UUID, card: Card)
    case proposeClaim(playerID: UUID, totalTricks: Int)
    case respondToClaim(playerID: UUID, accepted: Bool)
    case counterClaim(playerID: UUID, totalTricks: Int)
    case cancelClaim(playerID: UUID?)
    case stateAdvanced(reason: String)
}

struct MultiplayerGameEvent: Codable, Identifiable {
    let id: String
    let roomID: String
    let revision: Int
    let actorPlayerID: String
    let createdAt: Date
    let action: MultiplayerGameAction
    let resultingState: MultiplayerGameState
}
