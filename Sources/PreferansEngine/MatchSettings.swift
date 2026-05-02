import Foundation

/// Whole-match settings: how many bullets close the pulka, what the raspasy
/// loop looks like, and whether totus is a special bid above misère or just
/// a regular 10-trick contract in the standard ladder.
///
/// Match settings sit alongside ``PreferansRules`` in the engine. ``rules``
/// configures *one deal*; ``MatchSettings`` configures the match those deals
/// are accumulating into.
public struct MatchSettings: Hashable, Codable, Sendable {
    /// Pulka closes when ``ScoreSheet/pool`` summed across all players reaches
    /// or exceeds this value. ``unbounded`` (`Int.max`) keeps the engine in
    /// the legacy "play deals forever" mode.
    public var poolTarget: Int
    public var raspasy: RaspasyPolicy
    public var totus: TotusPolicy

    public init(
        poolTarget: Int = .max,
        raspasy: RaspasyPolicy = .singleShot,
        totus: TotusPolicy = .asTenTrickGame(requireWhist: false)
    ) {
        self.poolTarget = poolTarget
        self.raspasy = raspasy
        self.totus = totus
    }

    /// No game-over gate, no totus bonus, single-shot raspasy. The shape the
    /// engine had before ``MatchSettings`` existed.
    public static let unbounded = MatchSettings()
}

public enum RaspasyPolicy: Hashable, Codable, Sendable {
    /// One all-pass deal then bidding resumes normally on the next deal.
    case singleShot
}

public enum TotusPolicy: Hashable, Codable, Sendable {
    /// Totus is just the 10-trick game contract in the standard ladder.
    /// ``requireWhist`` flips ``PreferansRules/requireWhistOnTenTrickContracts``.
    case asTenTrickGame(requireWhist: Bool)

    /// Totus is its own bid sitting above misère. Declarer takes the talon,
    /// discards two, then picks the trump strain; opponents are forced to
    /// whist when ``requireWhist`` is true. ``bonusPool`` is added to the
    /// declarer's pool *only* when the contract is made.
    case dedicatedContract(requireWhist: Bool, bonusPool: Int)

    public var isDedicated: Bool {
        if case .dedicatedContract = self { return true }
        return false
    }

    public var bonusPool: Int {
        if case let .dedicatedContract(_, bonus) = self { return bonus }
        return 0
    }

    public var requireWhistOnTenTricks: Bool {
        switch self {
        case let .asTenTrickGame(requireWhist), let .dedicatedContract(requireWhist, _):
            return requireWhist
        }
    }
}

/// Snapshot returned when the engine transitions to ``DealState/gameOver``.
/// Captures the final scoresheet, the deal that pushed the pool past the
/// target, and a stable standings list (highest balance first).
public struct MatchSummary: Equatable, Codable, Sendable {
    public let finalScore: ScoreSheet
    public let dealsPlayed: Int
    public let lastDeal: DealResult
    public let standings: [Standing]

    public struct Standing: Equatable, Codable, Sendable {
        public let player: PlayerID
        public let balance: Double
        public let pool: Int
        public let mountain: Int

        public init(player: PlayerID, balance: Double, pool: Int, mountain: Int) {
            self.player = player
            self.balance = balance
            self.pool = pool
            self.mountain = mountain
        }
    }

    public init(finalScore: ScoreSheet, dealsPlayed: Int, lastDeal: DealResult, standings: [Standing]) {
        self.finalScore = finalScore
        self.dealsPlayed = dealsPlayed
        self.lastDeal = lastDeal
        self.standings = standings
    }
}
