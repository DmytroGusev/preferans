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

    public var title: String {
        switch self {
        case .waitingForDeal: return "Waiting for deal"
        case .bidding: return "Bidding"
        case .awaitingDiscard: return "Talon exchange"
        case .awaitingContract: return "Declare contract"
        case .awaitingWhist: return "Whist"
        case .awaitingDefenderMode: return "Defender mode"
        case .playing: return "Playing"
        case .dealFinished: return "Deal finished"
        case .gameOver: return "Game over"
        }
    }
}

public struct LegalActionProjection: Codable, Sendable, Equatable {
    public var canStartDeal: Bool
    public var bidCalls: [BidCall]
    public var whistCalls: [WhistCall]
    public var playableCards: [Card]
    public var contractOptions: [GameContract]
    public var defenderModes: [DefenderPlayMode]
    public var canDiscard: Bool

    public init(
        canStartDeal: Bool = false,
        bidCalls: [BidCall] = [],
        whistCalls: [WhistCall] = [],
        playableCards: [Card] = [],
        contractOptions: [GameContract] = [],
        defenderModes: [DefenderPlayMode] = [],
        canDiscard: Bool = false
    ) {
        self.canStartDeal = canStartDeal
        self.bidCalls = bidCalls
        self.whistCalls = whistCalls
        self.playableCards = playableCards
        self.contractOptions = contractOptions
        self.defenderModes = defenderModes
        self.canDiscard = canDiscard
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
    public var message: String
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
        var message = ""
        var revealOpenHandOwners = Set<PlayerID>()

        switch engine.state {
        case .waitingForDeal:
            phase = .waitingForDeal(nextDealer: engine.nextDealer)
            legal.canStartDeal = true
            message = "Start the next deal."

        case let .bidding(state):
            dealer = state.dealer
            activePlayers = state.activePlayers
            hands = state.hands
            talonCards = state.talon
            auction = state.calls
            currentActor = state.currentPlayer
            phase = .bidding(currentPlayer: state.currentPlayer, highestBid: state.highestBid)
            legal.bidCalls = engine.legalBidCalls(for: viewer)
            message = "Auction: \(state.currentPlayer.rawValue) to call."
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
            message = "\(state.declarer.rawValue) takes the talon and discards two cards."
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
            message = state.finalBid == .totus
                ? "\(state.declarer.rawValue) picks the totus strain."
                : "\(state.declarer.rawValue) declares a final contract."
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
            message = "Whist decision: \(state.currentPlayer.rawValue)."
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
            message = "\(state.whister.rawValue) chooses open or closed defender play."
            markActiveRoles(activePlayers, into: &roleMap)

        case let .playing(state):
            dealer = state.dealer
            activePlayers = state.activePlayers
            hands = state.hands
            talonCards = state.talon
            discardCards = state.discard
            currentActor = state.currentPlayer
            currentTrick = state.currentTrick
            completedTrickCount = state.completedTricks.count
            trickCounts = state.trickCounts
            legal.playableCards = engine.legalCards(for: viewer)
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
            case .allPass:
                projectedKind = .allPass
            }
            phase = .playing(currentPlayer: state.currentPlayer, leader: state.leader, kind: projectedKind)
            message = "Trick \(state.completedTricks.count + 1): \(state.currentPlayer.rawValue) to play."
            markActiveRoles(activePlayers, into: &roleMap)

        case let .dealFinished(result):
            activePlayers = result.activePlayers
            completedTrickCount = result.completedTricks.count
            trickCounts = result.trickCounts
            phase = .dealFinished(result: result)
            legal.canStartDeal = true
            message = "Deal scored. Start the next deal when ready."
            markActiveRoles(activePlayers, into: &roleMap)

        case let .gameOver(summary):
            activePlayers = summary.lastDeal.activePlayers
            completedTrickCount = summary.lastDeal.completedTricks.count
            trickCounts = summary.lastDeal.trickCounts
            phase = .gameOver(summary: summary)
            legal.canStartDeal = false
            let winner = summary.standings.first?.player.rawValue ?? "—"
            message = "Game over. Winner: \(winner)."
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
            let role: SeatRole = isDealer && !isActive ? .dealer : (roleMap[player] ?? (isActive ? .active : .sittingOut))
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
            message: message
        )
    }

    private static func markActiveRoles(_ players: [PlayerID], into roleMap: inout [PlayerID: SeatRole]) {
        for player in players where roleMap[player] == nil {
            roleMap[player] = .active
        }
    }

    private static func projectTalon(_ talon: [Card], state: DealState, viewer: PlayerID, revealAll: Bool) -> [ProjectedCard] {
        if revealAll { return talon.sorted().map(ProjectedCard.known) }
        switch state {
        case let .awaitingDiscard(exchange) where exchange.declarer == viewer:
            return talon.sorted().map(ProjectedCard.known)
        default:
            return Array(repeating: .hidden, count: talon.count)
        }
    }

    private static func projectDiscard(
        _ discard: [Card],
        state: DealState,
        viewer: PlayerID,
        revealAll: Bool,
        revealDeclarerDiscardToDeclarer: Bool
    ) -> [ProjectedCard] {
        guard !discard.isEmpty else { return [] }
        if revealAll { return discard.sorted().map(ProjectedCard.known) }
        guard revealDeclarerDiscardToDeclarer else {
            return Array(repeating: .hidden, count: discard.count)
        }
        switch state {
        case let .awaitingContract(declaration) where declaration.declarer == viewer:
            return discard.sorted().map(ProjectedCard.known)
        case let .awaitingWhist(whist) where whist.declarer == viewer:
            return discard.sorted().map(ProjectedCard.known)
        case let .awaitingDefenderMode(mode) where mode.declarer == viewer:
            return discard.sorted().map(ProjectedCard.known)
        case let .playing(playing):
            if case let .game(context) = playing.kind, context.declarer == viewer {
                return discard.sorted().map(ProjectedCard.known)
            }
            if case let .misere(context) = playing.kind, context.declarer == viewer {
                return discard.sorted().map(ProjectedCard.known)
            }
            return Array(repeating: .hidden, count: discard.count)
        default:
            return Array(repeating: .hidden, count: discard.count)
        }
    }
}
