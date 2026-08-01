import Foundation

/// Whole-match settings: how many bullets close the pulka, what the raspasy
/// loop looks like, and whether totus is a special bid above misère or just
/// a regular 10-trick contract in the standard ladder.
///
/// Match settings sit alongside ``PreferansRules`` in the engine. ``rules``
/// configures *one deal*; ``MatchSettings`` configures the match those deals
/// are accumulating into.
public struct MatchSettings: Hashable, Codable, Sendable {
    /// Total table pulka target. The UI stores a per-player length multiplied
    /// by player count, so a 3-player short pulka of 11 is represented as 33.
    /// ``poolClosure`` determines whether that total represents equal
    /// individual limits (Sochi) or one shared table total (Leningrad).
    /// ``unbounded`` (`Int.max`) keeps the engine in the legacy "play deals
    /// forever" mode.
    public var poolTarget: Int
    public var poolClosure: PoolClosurePolicy
    public var raspasy: RaspasyPolicy
    public var totus: TotusPolicy

    public init(
        poolTarget: Int = .max,
        poolClosure: PoolClosurePolicy = .individualWithAmericanAid,
        raspasy: RaspasyPolicy = .sochi,
        totus: TotusPolicy = .asTenTrickGame(requireWhist: false)
    ) {
        self.poolTarget = poolTarget
        self.poolClosure = poolClosure
        self.raspasy = raspasy
        self.totus = totus
    }

    /// No game-over gate and no dedicated totus bonus. Deal rules still use
    /// the canonical Sochi raspasy series so an unbounded practice table plays
    /// the same auctions and scores as a bounded one.
    public static let unbounded = MatchSettings()

    /// Validation that does not depend on a table's seat count. Kept beside
    /// the data so decoding and engine construction cannot drift into
    /// different definitions of a valid match configuration.
    var intrinsicConfigurationError: String? {
        if poolTarget != .max && poolTarget <= 0 {
            return "Pool target must be positive or unbounded."
        }
        if case let .dedicatedContract(_, bonusPool) = totus, bonusPool < 0 {
            return "Dedicated Totus bonus pool cannot be negative."
        }
        return nil
    }

    func configurationError(playerCount: Int) -> String? {
        if let error = intrinsicConfigurationError { return error }
        guard playerCount > 0 else { return "Player count must be positive." }
        if poolTarget != .max,
           poolClosure == .individualWithAmericanAid,
           !poolTarget.isMultiple(of: playerCount) {
            return "Individual pool target \(poolTarget) must divide evenly across \(playerCount) players."
        }
        return nil
    }

    /// Whether the current score has closed the match. Keeping this decision
    /// beside the policy prevents scoring, game-over transitions, and snapshot
    /// invariants from growing subtly different definitions of "closed".
    func isPoolClosed(_ score: ScoreSheet) -> Bool {
        guard poolTarget != .max else { return false }
        switch poolClosure {
        case .individualWithAmericanAid:
            guard poolTarget > 0,
                  poolTarget.isMultiple(of: score.players.count) else {
                return false
            }
            let target = poolTarget / score.players.count
            return score.players.allSatisfy { (score.pool[$0] ?? 0) >= target }
        case .tableTotal:
            return score.pool.values.reduce(0, +) >= poolTarget
        }
    }

    private enum CodingKeys: String, CodingKey {
        case poolTarget
        case poolClosure
        case raspasy
        case totus
    }

    /// Snapshots written before pool closure became explicit were all using
    /// the Sochi-style individual/American-aid behavior.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = MatchSettings(
            poolTarget: try values.decodeIfPresent(Int.self, forKey: .poolTarget) ?? .max,
            poolClosure: try values.decodeIfPresent(PoolClosurePolicy.self, forKey: .poolClosure)
                ?? .individualWithAmericanAid,
            raspasy: try values.decodeIfPresent(RaspasyPolicy.self, forKey: .raspasy) ?? .singleShot,
            totus: try values.decodeIfPresent(TotusPolicy.self, forKey: .totus)
                ?? .asTenTrickGame(requireWhist: false)
        )
        if let error = decoded.intrinsicConfigurationError {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: error
            ))
        }
        self = decoded
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(poolTarget, forKey: .poolTarget)
        try values.encode(poolClosure, forKey: .poolClosure)
        try values.encode(raspasy, forKey: .raspasy)
        try values.encode(totus, forKey: .totus)
    }
}

/// Pulka-closing conventions are deliberately match-level rather than score
/// multipliers. Sochi closes every player's individual pool and redirects
/// surplus via American aid; Leningrad never closes an individual pool and
/// simply stops once the table's combined pool reaches the agreed total.
public enum PoolClosurePolicy: String, Hashable, Codable, Sendable {
    case individualWithAmericanAid
    case tableTotal
}

/// How the price of consecutive raspasy deals grows. The multiplier is
/// applied to the convention's base all-pass price: Sochi's base is 1, while
/// Leningrad's is 2, so the same arithmetic progression records 1–2–3 and
/// 2–4–6 respectively.
public enum RaspasyPenaltyProgression: String, Hashable, Codable, Sendable {
    /// 1–1–1…
    case flat
    /// 1–2–3–3…
    case arithmetic
    /// 1–2–2…
    case cappedDouble
    /// 1–2–4–4…
    case geometric
}

/// Minimum game contract that may be bid as a raspasy series deepens.
/// Misère and a dedicated totus remain legal special bids at every stage.
public enum RaspasyExitProgression: String, Hashable, Codable, Sendable {
    /// 6–6–6…
    case simple
    /// 6–7–7…
    case constrained
    /// 6–7–8–8…
    case strict
}

public enum RaspasyPolicy: Hashable, Codable, Sendable {
    /// Legacy behavior retained for old fixtures and decoded snapshots: one
    /// all-pass price and an ordinary six-level auction after every deal.
    case singleShot

    /// Consecutive all-pass deals share a persistent progression stage. A
    /// non-raspasy result resets both the price and the exit requirement.
    case progressive(
        penalties: RaspasyPenaltyProgression,
        exit: RaspasyExitProgression
    )

    /// App defaults used until the table chooses its house settings. Raspasy
    /// price and exit progressions are negotiated options in both named
    /// conventions; the lobby transports the selected pair in MatchSettings.
    /// Leningrad's doubled base all-pass value turns trick penalties into
    /// 2–4–6; the separate clean-exit pool credit remains 1–2–3.
    public static let sochi = RaspasyPolicy.progressive(
        penalties: .arithmetic,
        exit: .strict
    )
    public static let leningrad = RaspasyPolicy.progressive(
        penalties: .arithmetic,
        exit: .strict
    )

    /// Multiplier for the *current* raspasy deal. `precedingDeals` is the
    /// number of immediately preceding deals that were also raspasy, so zero
    /// is the first deal in a series.
    public func scoreMultiplier(precededBy precedingDeals: Int) -> Int {
        let stage = max(0, precedingDeals)
        switch self {
        case .singleShot:
            return 1
        case let .progressive(penalties, _):
            switch penalties {
            case .flat:
                return 1
            case .arithmetic:
                return min(stage, 2) + 1
            case .cappedDouble:
                return min(stage, 1) + 1
            case .geometric:
                return [1, 2, 4][min(stage, 2)]
            }
        }
    }

    /// Minimum trick count for an ordinary game bid in the next auction.
    /// `precedingDeals == 1` means one raspasy has just been scored.
    public func minimumGameTricks(after precedingDeals: Int) -> Int {
        let stage = max(0, precedingDeals)
        switch self {
        case .singleShot:
            return 6
        case let .progressive(_, exit):
            switch exit {
            case .simple:
                return 6
            case .constrained:
                return stage == 0 ? 6 : 7
            case .strict:
                return 6 + min(stage, 2)
            }
        }
    }
}

public enum TotusPolicy: Hashable, Codable, Sendable {
    /// Totus is just the 10-trick game contract in the standard ladder.
    /// When `requireWhist` is true (or the rules variant sets
    /// ``PreferansRules/requireWhistOnTenTrickContracts``), a declared 10-trick
    /// contract goes through the ordinary defender whist/pass decision. Any
    /// defender who whists takes on the defense's 1-trick scoring quota.
    case asTenTrickGame(requireWhist: Bool)

    /// Totus is its own bid sitting above misère. Declarer takes the talon,
    /// discards two, then picks the trump strain and starts play immediately.
    /// ``requireWhist`` is retained for compatibility with saved settings;
    /// it applies to the standard 10-trick ladder, not this dedicated flow.
    /// ``bonusPool`` is added to the declarer's pool *only* when made.
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
