import Foundation

public enum DealState: Equatable, Codable, Sendable, CustomStringConvertible {
    case waitingForDeal
    case bidding(BiddingState)
    case awaitingDiscard(ExchangeState)
    case awaitingContract(ContractDeclarationState)
    case awaitingWhist(WhistState)
    case awaitingDefenderMode(DefenderModeState)
    case playing(PlayingState)
    case dealFinished(DealResult)
    /// Terminal state. Reached when applying a deal's score pushes the pool
    /// total to or past ``MatchSettings/poolTarget``. ``startDeal`` from this
    /// state throws — the match is closed.
    case gameOver(MatchSummary)

    public var description: String {
        switch self {
        case .waitingForDeal: return "waitingForDeal"
        case .bidding: return "bidding"
        case .awaitingDiscard: return "awaitingDiscard"
        case .awaitingContract: return "awaitingContract"
        case .awaitingWhist: return "awaitingWhist"
        case .awaitingDefenderMode: return "awaitingDefenderMode"
        case .playing: return "playing"
        case .dealFinished: return "dealFinished"
        case .gameOver: return "gameOver"
        }
    }
}

public struct BiddingState: Equatable, Codable, Sendable {
    public let dealer: PlayerID
    public let activePlayers: [PlayerID]
    public var hands: [PlayerID: [Card]]
    public let talon: [Card]
    public var currentPlayer: PlayerID
    public var passed: Set<PlayerID>
    public var highestBid: ContractBid?
    public var highestBidder: PlayerID?
    public var calls: [AuctionCall]
    public var significantBidByPlayer: [PlayerID: ContractBid]

    public init(
        dealer: PlayerID,
        activePlayers: [PlayerID],
        hands: [PlayerID: [Card]],
        talon: [Card],
        currentPlayer: PlayerID,
        passed: Set<PlayerID> = [],
        highestBid: ContractBid? = nil,
        highestBidder: PlayerID? = nil,
        calls: [AuctionCall] = [],
        significantBidByPlayer: [PlayerID: ContractBid] = [:]
    ) {
        self.dealer = dealer
        self.activePlayers = activePlayers
        self.hands = hands
        self.talon = talon
        self.currentPlayer = currentPlayer
        self.passed = passed
        self.highestBid = highestBid
        self.highestBidder = highestBidder
        self.calls = calls
        self.significantBidByPlayer = significantBidByPlayer
    }
}

public struct ExchangeState: Equatable, Codable, Sendable {
    public let dealer: PlayerID
    public let activePlayers: [PlayerID]
    public var hands: [PlayerID: [Card]]
    public let talon: [Card]
    public let declarer: PlayerID
    public let finalBid: ContractBid
    public let auction: [AuctionCall]

    public init(
        dealer: PlayerID,
        activePlayers: [PlayerID],
        hands: [PlayerID: [Card]],
        talon: [Card],
        declarer: PlayerID,
        finalBid: ContractBid,
        auction: [AuctionCall]
    ) {
        self.dealer = dealer
        self.activePlayers = activePlayers
        self.hands = hands
        self.talon = talon
        self.declarer = declarer
        self.finalBid = finalBid
        self.auction = auction
    }
}

public struct ContractDeclarationState: Equatable, Codable, Sendable {
    public let dealer: PlayerID
    public let activePlayers: [PlayerID]
    public var hands: [PlayerID: [Card]]
    public let talon: [Card]
    public let discard: [Card]
    public let declarer: PlayerID
    public let finalBid: ContractBid
    public let auction: [AuctionCall]

    public init(
        dealer: PlayerID,
        activePlayers: [PlayerID],
        hands: [PlayerID: [Card]],
        talon: [Card],
        discard: [Card],
        declarer: PlayerID,
        finalBid: ContractBid,
        auction: [AuctionCall]
    ) {
        self.dealer = dealer
        self.activePlayers = activePlayers
        self.hands = hands
        self.talon = talon
        self.discard = discard
        self.declarer = declarer
        self.finalBid = finalBid
        self.auction = auction
    }
}

public struct WhistState: Equatable, Codable, Sendable {
    public enum HalfWhistFlow: Equatable, Codable, Sendable {
        case normal
        case firstDefenderSecondChance(halfWhister: PlayerID)
    }

    public let dealer: PlayerID
    public let activePlayers: [PlayerID]
    public var hands: [PlayerID: [Card]]
    public let talon: [Card]
    public let discard: [Card]
    public let declarer: PlayerID
    public let contract: GameContract
    public let defenders: [PlayerID]
    public var currentPlayer: PlayerID
    public var calls: [WhistCallRecord]
    public var flow: HalfWhistFlow
    /// Bonus pool credited to the declarer if (and only if) the contract
    /// makes. Non-zero only when the auction-winning bid was ``ContractBid/totus``
    /// in a ``TotusPolicy/dedicatedContract`` match.
    public let bonusPoolOnSuccess: Int

    public init(
        dealer: PlayerID,
        activePlayers: [PlayerID],
        hands: [PlayerID: [Card]],
        talon: [Card],
        discard: [Card],
        declarer: PlayerID,
        contract: GameContract,
        defenders: [PlayerID],
        currentPlayer: PlayerID,
        calls: [WhistCallRecord] = [],
        flow: HalfWhistFlow = .normal,
        bonusPoolOnSuccess: Int = 0
    ) {
        self.dealer = dealer
        self.activePlayers = activePlayers
        self.hands = hands
        self.talon = talon
        self.discard = discard
        self.declarer = declarer
        self.contract = contract
        self.defenders = defenders
        self.currentPlayer = currentPlayer
        self.calls = calls
        self.flow = flow
        self.bonusPoolOnSuccess = bonusPoolOnSuccess
    }
}

public struct DefenderModeState: Equatable, Codable, Sendable {
    public let dealer: PlayerID
    public let activePlayers: [PlayerID]
    public var hands: [PlayerID: [Card]]
    public let talon: [Card]
    public let discard: [Card]
    public let declarer: PlayerID
    public let contract: GameContract
    public let defenders: [PlayerID]
    public let whister: PlayerID
    public let whistCalls: [WhistCallRecord]
    public let bonusPoolOnSuccess: Int

    public init(
        dealer: PlayerID,
        activePlayers: [PlayerID],
        hands: [PlayerID: [Card]],
        talon: [Card],
        discard: [Card],
        declarer: PlayerID,
        contract: GameContract,
        defenders: [PlayerID],
        whister: PlayerID,
        whistCalls: [WhistCallRecord],
        bonusPoolOnSuccess: Int = 0
    ) {
        self.dealer = dealer
        self.activePlayers = activePlayers
        self.hands = hands
        self.talon = talon
        self.discard = discard
        self.declarer = declarer
        self.contract = contract
        self.defenders = defenders
        self.whister = whister
        self.whistCalls = whistCalls
        self.bonusPoolOnSuccess = bonusPoolOnSuccess
    }
}

public struct GamePlayContext: Equatable, Codable, Sendable {
    public let declarer: PlayerID
    public let contract: GameContract
    public let defenders: [PlayerID]
    public let whisters: [PlayerID]
    public let defenderPlayMode: DefenderPlayMode
    public let whistCalls: [WhistCallRecord]
    public let bonusPoolOnSuccess: Int

    public init(
        declarer: PlayerID,
        contract: GameContract,
        defenders: [PlayerID],
        whisters: [PlayerID],
        defenderPlayMode: DefenderPlayMode,
        whistCalls: [WhistCallRecord],
        bonusPoolOnSuccess: Int = 0
    ) {
        self.declarer = declarer
        self.contract = contract
        self.defenders = defenders
        self.whisters = whisters
        self.defenderPlayMode = defenderPlayMode
        self.whistCalls = whistCalls
        self.bonusPoolOnSuccess = bonusPoolOnSuccess
    }
}

public struct MiserePlayContext: Equatable, Codable, Sendable {
    public let declarer: PlayerID

    public init(declarer: PlayerID) {
        self.declarer = declarer
    }
}

public struct AllPassPlayContext: Equatable, Codable, Sendable {
    public let talonPolicy: PreferansRules.AllPassTalonPolicy

    public init(talonPolicy: PreferansRules.AllPassTalonPolicy) {
        self.talonPolicy = talonPolicy
    }
}

public enum PlayKind: Equatable, Codable, Sendable {
    case game(GamePlayContext)
    case misere(MiserePlayContext)
    case allPass(AllPassPlayContext)

    public var trumpSuit: Suit? {
        switch self {
        case let .game(context): return context.contract.strain.suit
        case .misere, .allPass: return nil
        }
    }
}

public struct PlayingState: Equatable, Codable, Sendable {
    public let dealer: PlayerID
    public let activePlayers: [PlayerID]
    public var hands: [PlayerID: [Card]]
    public let talon: [Card]
    public let discard: [Card]
    public var leader: PlayerID
    public var currentPlayer: PlayerID
    public var currentTrick: [CardPlay]
    public var completedTricks: [Trick]
    public var trickCounts: [PlayerID: Int]
    public let kind: PlayKind

    public init(
        dealer: PlayerID,
        activePlayers: [PlayerID],
        hands: [PlayerID: [Card]],
        talon: [Card],
        discard: [Card] = [],
        leader: PlayerID,
        currentPlayer: PlayerID,
        currentTrick: [CardPlay] = [],
        completedTricks: [Trick] = [],
        trickCounts: [PlayerID: Int]? = nil,
        kind: PlayKind
    ) {
        self.dealer = dealer
        self.activePlayers = activePlayers
        self.hands = hands
        self.talon = talon
        self.discard = discard
        self.leader = leader
        self.currentPlayer = currentPlayer
        self.currentTrick = currentTrick
        self.completedTricks = completedTricks
        self.trickCounts = trickCounts ?? Dictionary(uniqueKeysWithValues: activePlayers.map { ($0, 0) })
        self.kind = kind
    }

    public var isComplete: Bool {
        completedTricks.count == 10
    }
}

public enum DealResultKind: Equatable, Codable, Sendable {
    case passedOut
    case halfWhist(declarer: PlayerID, contract: GameContract, halfWhister: PlayerID)
    case game(declarer: PlayerID, contract: GameContract, whisters: [PlayerID])
    case misere(declarer: PlayerID)
    case allPass
}

public struct DealResult: Equatable, Codable, Sendable {
    public let kind: DealResultKind
    public let activePlayers: [PlayerID]
    public let trickCounts: [PlayerID: Int]
    public let completedTricks: [Trick]
    public let scoreDelta: ScoreDelta

    public init(
        kind: DealResultKind,
        activePlayers: [PlayerID],
        trickCounts: [PlayerID: Int],
        completedTricks: [Trick],
        scoreDelta: ScoreDelta
    ) {
        self.kind = kind
        self.activePlayers = activePlayers
        self.trickCounts = trickCounts
        self.completedTricks = completedTricks
        self.scoreDelta = scoreDelta
    }
}

public enum PreferansEvent: Equatable, Codable, Sendable {
    case dealStarted(dealer: PlayerID, activePlayers: [PlayerID])
    case bidAccepted(AuctionCall)
    case auctionWon(declarer: PlayerID, bid: ContractBid)
    case allPassed
    case talonExchanged(declarer: PlayerID, talon: [Card], discard: [Card])
    case contractDeclared(declarer: PlayerID, contract: GameContract)
    case whistAccepted(WhistCallRecord)
    case defenderModeChosen(whister: PlayerID, mode: DefenderPlayMode)
    case playStarted(PlayKind)
    case cardPlayed(CardPlay)
    case trickCompleted(Trick)
    case dealScored(DealResult)
    case matchEnded(MatchSummary)
}

public enum PreferansAction: Equatable, Codable, Sendable {
    case startDeal(dealer: PlayerID?, deck: [Card]?)
    case bid(player: PlayerID, call: BidCall)
    case discard(player: PlayerID, cards: [Card])
    case declareContract(player: PlayerID, contract: GameContract)
    case whist(player: PlayerID, call: WhistCall)
    case chooseDefenderMode(player: PlayerID, mode: DefenderPlayMode)
    case playCard(player: PlayerID, card: Card)
}

public struct PreferansSnapshot: Equatable, Codable, Sendable {
    public var players: [PlayerID]
    public var rules: PreferansRules
    public var match: MatchSettings
    public var state: DealState
    public var score: ScoreSheet
    public var nextDealer: PlayerID
    public var dealsPlayed: Int

    public init(
        players: [PlayerID],
        rules: PreferansRules,
        match: MatchSettings = .unbounded,
        state: DealState,
        score: ScoreSheet,
        nextDealer: PlayerID,
        dealsPlayed: Int = 0
    ) {
        self.players = players
        self.rules = rules
        self.match = match
        self.state = state
        self.score = score
        self.nextDealer = nextDealer
        self.dealsPlayed = dealsPlayed
    }
}
