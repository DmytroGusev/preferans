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

    /// Seat the engine is waiting on, or `nil` between deals / after the
    /// match has closed. Single source of truth for "whose turn is it" —
    /// view models, projections, and bot dispatchers all read from here.
    public var currentActor: PlayerID? {
        switch self {
        case let .bidding(s):              return s.currentPlayer
        case let .awaitingDiscard(s):      return s.declarer
        case let .awaitingContract(s):     return s.declarer
        case let .awaitingWhist(s):        return s.currentPlayer
        case let .awaitingDefenderMode(s): return s.whister
        case let .playing(s):              return s.currentPlayer
        case .waitingForDeal, .dealFinished, .gameOver:
            return nil
        }
    }

    /// The declarer of the current deal, when one has been determined —
    /// any state from ``awaitingDiscard`` through ``playing`` (game/misère
    /// kinds). `nil` during bidding (no winner yet), all-pass play, and
    /// between deals. Used by projections to decide which seats can see
    /// the talon and the discard pile.
    public var declarer: PlayerID? {
        switch self {
        case let .awaitingDiscard(s):      return s.declarer
        case let .awaitingContract(s):     return s.declarer
        case let .awaitingWhist(s):        return s.declarer
        case let .awaitingDefenderMode(s): return s.declarer
        case let .playing(s):
            switch s.kind {
            case let .game(ctx):    return ctx.declarer
            case let .misere(ctx):  return ctx.declarer
            case .allPass:          return nil
            }
        case .bidding, .waitingForDeal, .dealFinished, .gameOver:
            return nil
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
    public var discard: [Card]
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
        self.trickCounts = trickCounts ?? activePlayers.dictionary(filledWith: 0)
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
    /// Each active player's original 10-card hand, before any prikup
    /// exchange, discard, or trick play. Older archived results may omit
    /// this payload, so consumers should treat `nil` as unavailable.
    public let initialHands: [PlayerID: [Card]]?

    public init(
        kind: DealResultKind,
        activePlayers: [PlayerID],
        trickCounts: [PlayerID: Int],
        completedTricks: [Trick],
        scoreDelta: ScoreDelta,
        initialHands: [PlayerID: [Card]]? = nil
    ) {
        self.kind = kind
        self.activePlayers = activePlayers
        self.trickCounts = trickCounts
        self.completedTricks = completedTricks
        self.scoreDelta = scoreDelta
        self.initialHands = initialHands
    }

    /// Result for a deal that ended before any card was played — `passedOut`
    /// (auction-won by default-grant) and `halfWhist`. No trick was taken
    /// by anyone, so `trickCounts` is zeroed and `completedTricks` empty.
    static func unplayed(
        kind: DealResultKind,
        activePlayers: [PlayerID],
        scoreDelta: ScoreDelta,
        initialHands: [PlayerID: [Card]]? = nil
    ) -> DealResult {
        DealResult(
            kind: kind,
            activePlayers: activePlayers,
            trickCounts: activePlayers.dictionary(filledWith: 0),
            completedTricks: [],
            scoreDelta: scoreDelta,
            initialHands: initialHands
        )
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

    /// Player whose seat the action speaks for, or `nil` for `startDeal`
    /// (which is dealer-driven and can be requested by any seat). Used by
    /// the host actor to detect spoofed actions arriving from the wrong
    /// GameKit sender.
    public var actor: PlayerID? {
        switch self {
        case .startDeal:
            return nil
        case let .bid(player, _),
             let .discard(player, _),
             let .declareContract(player, _),
             let .whist(player, _),
             let .chooseDefenderMode(player, _),
             let .playCard(player, _):
            return player
        }
    }
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
