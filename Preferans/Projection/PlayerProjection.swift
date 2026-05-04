import Foundation
import PreferansEngine

public enum ProjectedCard: Codable, Sendable, Hashable, CustomStringConvertible {
    case known(Card)
    case hidden

    public var description: String {
        switch self {
        case .known(let card): return card.description
        case .hidden: return "🂠"
        }
    }

    public var knownCard: Card? {
        if case let .known(card) = self { return card }
        return nil
    }
}

public enum SeatRole: String, Codable, Sendable, Hashable {
    case dealer
    case declarer
    case defender
    case whister
    case halfWhister
    case active
    case sittingOut
}

public struct SeatProjection: Codable, Sendable, Hashable, Identifiable {
    public var id: PlayerID { player }
    public var player: PlayerID
    public var displayName: String
    public var isActive: Bool
    public var isDealer: Bool
    public var isCurrentActor: Bool
    public var role: SeatRole
    public var hand: [ProjectedCard]
    public var trickCount: Int

    public init(
        player: PlayerID,
        displayName: String,
        isActive: Bool,
        isDealer: Bool,
        isCurrentActor: Bool,
        role: SeatRole,
        hand: [ProjectedCard],
        trickCount: Int
    ) {
        self.player = player
        self.displayName = displayName
        self.isActive = isActive
        self.isDealer = isDealer
        self.isCurrentActor = isCurrentActor
        self.role = role
        self.hand = hand
        self.trickCount = trickCount
    }
}

public enum ProjectedPlayKind: Codable, Sendable, Hashable {
    case game(declarer: PlayerID, contract: GameContract, defenders: [PlayerID], whisters: [PlayerID], defenderPlayMode: DefenderPlayMode)
    case misere(declarer: PlayerID)
    case allPass
}

public enum ProjectedPhase: Codable, Sendable, Equatable {
    case waitingForDeal(nextDealer: PlayerID)
    case bidding(currentPlayer: PlayerID, highestBid: ContractBid?)
    case awaitingDiscard(declarer: PlayerID, finalBid: ContractBid)
    case awaitingContract(declarer: PlayerID, finalBid: ContractBid)
    case awaitingWhist(currentPlayer: PlayerID, declarer: PlayerID, contract: GameContract)
    case awaitingDefenderMode(whister: PlayerID, contract: GameContract)
    case playing(currentPlayer: PlayerID, leader: PlayerID, kind: ProjectedPlayKind)
    case dealFinished(result: DealResult)
    case gameOver(summary: MatchSummary)
}

/// Typed status describing what the table is doing right now. Each case
/// names the actor (and any minimal context the UI needs) so the catalog
/// can render a localized phrase at display time.
///
/// Replaces the older runtime-English `message: String` field. Localizing
/// the *output* only would have required parsing English strings; carrying
/// the actor as `PlayerID` keeps every renderer free to pull the display
/// name from `identities` and translate the surrounding sentence.
public enum ProjectedStatus: Codable, Sendable, Equatable {
    /// Pre-deal — engine is between deals (or before the first one).
    case readyToDeal
    /// Bidding phase — `currentPlayer` is the next to bid.
    case bidding(currentPlayer: PlayerID)
    /// Declarer is picking up the prikup and discarding two cards.
    case takingPrikup(declarer: PlayerID)
    /// Declarer is naming the contract. `pickingTotusStrain` is true when
    /// the contract narrowing is the totus-strain pick (10-trick contracts
    /// only) versus a general post-bid declaration.
    case namingContract(declarer: PlayerID, pickingTotusStrain: Bool)
    /// A defender is calling whist.
    case callingWhist(currentPlayer: PlayerID)
    /// The whister is choosing open or closed defender play.
    case choosingDefenderMode(whister: PlayerID)
    /// Trick-play — `currentPlayer` is the next to play. `trickNumber` is
    /// 1-indexed; rendered as "Trick 4: Anna" (etc.).
    case playingTrick(currentPlayer: PlayerID, trickNumber: Int)
    /// A settlement proposal is waiting on player responses.
    case settling(proposer: PlayerID, target: PlayerID, targetTricks: Int, currentPlayer: PlayerID?)
    /// Deal scored; the result sheet is presenting outcomes.
    case dealScored
    /// Match over. `winner` is the standings leader (nil if no standings).
    case matchOver(winner: PlayerID?)
}

public struct LegalActionProjection: Codable, Sendable, Equatable {
    public var canStartDeal: Bool
    public var bidCalls: [BidCall]
    public var whistCalls: [WhistCall]
    public var playableCards: [Card]
    public var contractOptions: [GameContract]
    public var defenderModes: [DefenderPlayMode]
    public var canDiscard: Bool
    public var settlementOptions: [TrickSettlement]
    public var pendingSettlement: TrickSettlementProposal?
    public var canAcceptSettlement: Bool
    public var canRejectSettlement: Bool

    public init(
        canStartDeal: Bool = false,
        bidCalls: [BidCall] = [],
        whistCalls: [WhistCall] = [],
        playableCards: [Card] = [],
        contractOptions: [GameContract] = [],
        defenderModes: [DefenderPlayMode] = [],
        canDiscard: Bool = false,
        settlementOptions: [TrickSettlement] = [],
        pendingSettlement: TrickSettlementProposal? = nil,
        canAcceptSettlement: Bool = false,
        canRejectSettlement: Bool = false
    ) {
        self.canStartDeal = canStartDeal
        self.bidCalls = bidCalls
        self.whistCalls = whistCalls
        self.playableCards = playableCards
        self.contractOptions = contractOptions
        self.defenderModes = defenderModes
        self.canDiscard = canDiscard
        self.settlementOptions = settlementOptions
        self.pendingSettlement = pendingSettlement
        self.canAcceptSettlement = canAcceptSettlement
        self.canRejectSettlement = canRejectSettlement
    }
}

public struct PlayerGameProjection: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID { tableID }
    public var tableID: UUID
    public var sequence: Int
    public var viewer: PlayerID
    public var players: [PlayerID]
    public var identities: [PlayerIdentity]
    public var rules: PreferansRules
    public var score: ScoreSheet
    public var phase: ProjectedPhase
    public var seats: [SeatProjection]
    public var auction: [AuctionCall]
    public var whistCalls: [WhistCallRecord]
    public var currentTrick: [CardPlay]
    public var completedTrickCount: Int
    public var trickCounts: [PlayerID: Int]
    public var talon: [ProjectedCard]
    public var discard: [ProjectedCard]
    public var legal: LegalActionProjection
    public var status: ProjectedStatus
}

public extension PlayerGameProjection {
    /// Resolve a player's display name from the carried `identities`,
    /// falling back to the raw `PlayerID` string when the table has no
    /// identity record for that seat. Replaces the inline
    /// `identities.first { ... }?.displayName ?? player.rawValue`
    /// pattern that used to live in every consumer.
    func displayName(for player: PlayerID) -> String {
        identities.first { $0.playerID == player }?.displayName ?? player.rawValue
    }
}

public struct ProjectionPolicy: Sendable, Equatable {
    public var revealAllHands: Bool
    public var revealOpenDefenderHandsToAll: Bool
    public var revealDeclarerDiscardToDeclarer: Bool

    public init(
        revealAllHands: Bool = false,
        revealOpenDefenderHandsToAll: Bool = true,
        revealDeclarerDiscardToDeclarer: Bool = true
    ) {
        self.revealAllHands = revealAllHands
        self.revealOpenDefenderHandsToAll = revealOpenDefenderHandsToAll
        self.revealDeclarerDiscardToDeclarer = revealDeclarerDiscardToDeclarer
    }

    public static let online = ProjectionPolicy()
    public static let localDebug = ProjectionPolicy(revealAllHands: true)
}

public enum PlayerProjectionBuilder {
    public static func projection(
        for viewer: PlayerID,
        tableID: UUID,
        sequence: Int,
        engine: PreferansEngine,
        identities: [PlayerIdentity] = [],
        policy: ProjectionPolicy = .online
    ) -> PlayerGameProjection {
        let identityMap = Dictionary(uniqueKeysWithValues: identities.map { ($0.playerID, $0.displayName) })
        let frame = phaseFrame(for: viewer, engine: engine, policy: policy)
        let seats = seatProjections(
            for: engine.players,
            viewer: viewer,
            identityMap: identityMap,
            frame: frame,
            policy: policy
        )

        let projectedTalon = projectTalon(
            frame.talonCards,
            state: engine.state,
            viewer: viewer,
            revealAll: policy.revealAllHands
        )
        let projectedDiscard = projectDiscard(
            frame.discardCards,
            state: engine.state,
            viewer: viewer,
            revealAll: policy.revealAllHands,
            revealDeclarerDiscardToDeclarer: policy.revealDeclarerDiscardToDeclarer
        )

        return PlayerGameProjection(
            tableID: tableID,
            sequence: sequence,
            viewer: viewer,
            players: engine.players,
            identities: identities,
            rules: engine.rules,
            score: engine.score,
            phase: frame.phase,
            seats: seats,
            auction: frame.auction,
            whistCalls: frame.whistCalls,
            currentTrick: frame.currentTrick,
            completedTrickCount: frame.completedTrickCount,
            trickCounts: frame.trickCounts,
            talon: projectedTalon,
            discard: projectedDiscard,
            legal: frame.legal,
            status: frame.status
        )
    }
}
