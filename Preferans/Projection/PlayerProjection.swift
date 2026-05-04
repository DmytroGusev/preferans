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

        var dealer: PlayerID? = nil
        var activePlayers: [PlayerID] = []
        var hands: [PlayerID: [Card]] = [:]
        var talonCards: [Card] = []
        var discardCards: [Card] = []
        var auction: [AuctionCall] = []
        var whistCalls: [WhistCallRecord] = []
        var currentTrick: [CardPlay] = []
        var completedTrickCount = 0
        var trickCounts: [PlayerID: Int] = [:]
        var currentActor: PlayerID? = nil
        var roleMap: [PlayerID: SeatRole] = [:]
        var phase: ProjectedPhase
        var legal = LegalActionProjection()
        var status: ProjectedStatus
        var revealOpenHandOwners = Set<PlayerID>()

        switch engine.state {
        case .waitingForDeal:
            phase = .waitingForDeal(nextDealer: engine.nextDealer)
            legal.canStartDeal = true
            status = .readyToDeal

        case let .bidding(state):
            dealer = state.dealer
            activePlayers = state.activePlayers
            hands = state.hands
            talonCards = state.talon
            auction = state.calls
            currentActor = state.currentPlayer
            phase = .bidding(currentPlayer: state.currentPlayer, highestBid: state.highestBid)
            legal.bidCalls = engine.legalBidCalls(for: viewer)
            status = .bidding(currentPlayer: state.currentPlayer)
            markActiveRoles(activePlayers, into: &roleMap)

        case let .awaitingDiscard(state):
            dealer = state.dealer
            activePlayers = state.activePlayers
            hands = state.hands
            talonCards = state.talon
            auction = state.auction
            currentActor = state.declarer
            roleMap[state.declarer] = .declarer
            phase = .awaitingDiscard(declarer: state.declarer, finalBid: state.finalBid)
            legal.canDiscard = viewer == state.declarer
            status = .takingPrikup(declarer: state.declarer)
            markActiveRoles(activePlayers, into: &roleMap)

        case let .awaitingContract(state):
            dealer = state.dealer
            activePlayers = state.activePlayers
            hands = state.hands
            talonCards = state.talon
            discardCards = state.discard
            auction = state.auction
            currentActor = state.declarer
            roleMap[state.declarer] = .declarer
            phase = .awaitingContract(declarer: state.declarer, finalBid: state.finalBid)
            // Use the engine's totus-aware list so dedicated-totus declarations
            // are constrained to 10-trick contracts (one per strain).
            legal.contractOptions = viewer == state.declarer ? engine.legalContractDeclarations(for: viewer) : []
            status = .namingContract(declarer: state.declarer, pickingTotusStrain: state.finalBid == .totus)
            markActiveRoles(activePlayers, into: &roleMap)

        case let .awaitingWhist(state):
            dealer = state.dealer
            activePlayers = state.activePlayers
            hands = state.hands
            talonCards = state.talon
            discardCards = state.discard
            whistCalls = state.calls
            currentActor = state.currentPlayer
            roleMap[state.declarer] = .declarer
            for defender in state.defenders { roleMap[defender] = .defender }
            phase = .awaitingWhist(currentPlayer: state.currentPlayer, declarer: state.declarer, contract: state.contract)
            legal.whistCalls = engine.legalWhistCalls(for: viewer)
            status = .callingWhist(currentPlayer: state.currentPlayer)
            markActiveRoles(activePlayers, into: &roleMap)

        case let .awaitingDefenderMode(state):
            dealer = state.dealer
            activePlayers = state.activePlayers
            hands = state.hands
            talonCards = state.talon
            discardCards = state.discard
            whistCalls = state.whistCalls
            currentActor = state.whister
            roleMap[state.declarer] = .declarer
            for defender in state.defenders { roleMap[defender] = defender == state.whister ? .whister : .defender }
            phase = .awaitingDefenderMode(whister: state.whister, contract: state.contract)
            legal.defenderModes = viewer == state.whister ? [.closed, .open] : []
            status = .choosingDefenderMode(whister: state.whister)
            markActiveRoles(activePlayers, into: &roleMap)

        case let .playing(state):
            dealer = state.dealer
            activePlayers = state.activePlayers
            hands = state.hands
            talonCards = state.talon
            discardCards = state.discard
            currentActor = engine.state.currentActor
            currentTrick = state.currentTrick
            completedTrickCount = state.completedTricks.count
            trickCounts = state.trickCounts
            legal.playableCards = engine.legalCards(for: viewer)
            legal.settlementOptions = engine.legalSettlements(for: viewer)
            legal.pendingSettlement = state.pendingSettlement
            legal.canAcceptSettlement = engine.canAcceptSettlement(player: viewer)
            legal.canRejectSettlement = engine.canRejectSettlement(player: viewer)
            let projectedKind: ProjectedPlayKind
            switch state.kind {
            case let .game(context):
                projectedKind = .game(
                    declarer: context.declarer,
                    contract: context.contract,
                    defenders: context.defenders,
                    whisters: context.whisters,
                    defenderPlayMode: context.defenderPlayMode
                )
                roleMap[context.declarer] = .declarer
                for defender in context.defenders { roleMap[defender] = context.whisters.contains(defender) ? .whister : .defender }
                if context.defenderPlayMode == .open && policy.revealOpenDefenderHandsToAll {
                    revealOpenHandOwners.formUnion(context.defenders)
                }
                whistCalls = context.whistCalls
            case let .misere(context):
                projectedKind = .misere(declarer: context.declarer)
                roleMap[context.declarer] = .declarer
                let defenders = activePlayers.filter { $0 != context.declarer }
                for defender in defenders { roleMap[defender] = .whister }
                revealOpenHandOwners.formUnion(defenders)
            case .allPass:
                projectedKind = .allPass
            }
            phase = .playing(currentPlayer: state.currentPlayer, leader: state.leader, kind: projectedKind)
            if let proposal = state.pendingSettlement {
                status = .settling(
                    proposer: proposal.proposer,
                    target: proposal.settlement.target,
                    targetTricks: proposal.settlement.targetTricks,
                    currentPlayer: engine.state.currentActor
                )
            } else {
                status = .playingTrick(
                    currentPlayer: state.currentPlayer,
                    trickNumber: state.completedTricks.count + 1
                )
            }
            markActiveRoles(activePlayers, into: &roleMap)

        case let .dealFinished(result):
            activePlayers = result.activePlayers
            completedTrickCount = result.completedTricks.count
            trickCounts = result.trickCounts
            phase = .dealFinished(result: result)
            legal.canStartDeal = true
            status = .dealScored
            markActiveRoles(activePlayers, into: &roleMap)

        case let .gameOver(summary):
            activePlayers = summary.lastDeal.activePlayers
            completedTrickCount = summary.lastDeal.completedTricks.count
            trickCounts = summary.lastDeal.trickCounts
            phase = .gameOver(summary: summary)
            legal.canStartDeal = false
            status = .matchOver(winner: summary.standings.first?.player)
            markActiveRoles(activePlayers, into: &roleMap)
        }

        let seats = engine.players.map { player in
            let cards = hands[player] ?? []
            let projectedHand: [ProjectedCard]
            if policy.revealAllHands || player == viewer || revealOpenHandOwners.contains(player) {
                projectedHand = cards.sorted().map(ProjectedCard.known)
            } else {
                projectedHand = Array(repeating: .hidden, count: cards.count)
            }

            let isActive = activePlayers.isEmpty ? true : activePlayers.contains(player)
            let isDealer = dealer == player
            let role: SeatRole = roleMap[player] ?? (isActive ? .active : .sittingOut)
            return SeatProjection(
                player: player,
                displayName: identityMap[player] ?? player.rawValue,
                isActive: isActive,
                isDealer: isDealer,
                isCurrentActor: currentActor == player,
                role: role,
                hand: projectedHand,
                trickCount: trickCounts[player] ?? 0
            )
        }

        let projectedTalon = projectTalon(
            talonCards,
            state: engine.state,
            viewer: viewer,
            revealAll: policy.revealAllHands
        )
        let projectedDiscard = projectDiscard(
            discardCards,
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
            phase: phase,
            seats: seats,
            auction: auction,
            whistCalls: whistCalls,
            currentTrick: currentTrick,
            completedTrickCount: completedTrickCount,
            trickCounts: trickCounts,
            talon: projectedTalon,
            discard: projectedDiscard,
            legal: legal,
            status: status
        )
    }

    private static func markActiveRoles(_ players: [PlayerID], into roleMap: inout [PlayerID: SeatRole]) {
        for player in players where roleMap[player] == nil {
            roleMap[player] = .active
        }
    }

    private static func projectTalon(_ talon: [Card], state: DealState, viewer: PlayerID, revealAll: Bool) -> [ProjectedCard] {
        // The prikup is opened publicly during the talon exchange. In
        // lead-suit all-pass play the talon also remains public because it
        // determines the suit everyone must follow on the first two tricks.
        return reveal(talon, when: revealAll || state.hasPublicTalon)
    }

    private static func projectDiscard(
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
