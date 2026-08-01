import Foundation

public struct PreferansRules: Hashable, Codable, Sendable {
    public enum SingleWhistScoring: String, Codable, Sendable {
        case greedy
        case ownHandOnly
        /// When the declarer fails, the lone whister and their passing partner
        /// split the defender-trick whists equally. A made contract remains
        /// greedy, and remise consolation is still written in full by each
        /// defender.
        case gentleman
    }

    public enum FailedDeclarerConsolation: String, Codable, Sendable {
        case none
        case eachDefender
    }

    public enum WhistResponsibility: String, Codable, Sendable {
        case responsible
        case semiResponsible
        case none
    }

    public enum AllPassTalonPolicy: Hashable, Codable, Sendable {
        case ignored
        /// Three-player raspasy uses each talon card only to set the opening
        /// suit. At a four-player table the sitting-out dealer owns those
        /// cards and may win either of the first two tricks.
        case classic
        /// House-rule compatibility: the talon sets the opening suit at every
        /// table size, but its rank can never win the trick.
        case leadSuitOnly
    }

    public enum AllPassPenaltyPolicy: Hashable, Codable, Sendable {
        case perTrick(multiplier: Int, amnesty: Bool)
    }

    /// Compensation written by the sitting-out dealer in a four-player game
    /// when the talon contains established trick combinations. It is a table
    /// agreement in some circles, so it remains explicit even though the
    /// canonical app profiles enable it.
    public enum DealerTalonCompensation: String, Codable, Sendable {
        case none
        case classic
    }

    public var allowSeniorHandHoldBid: Bool
    public var requireWhistOnTenTrickContracts: Bool
    /// Optional Stalingrad convention: both defenders must whist, with
    /// closed hands, against a six-spade contract. This is a table agreement,
    /// not an intrinsic part of either the Sochi or Leningrad profile.
    public var forceWhistOnSixSpades: Bool
    public var singleWhistScoring: SingleWhistScoring
    public var failedDeclarerConsolation: FailedDeclarerConsolation
    public var whistResponsibility: WhistResponsibility
    public var allPassTalonPolicy: AllPassTalonPolicy
    public var allPassPenaltyPolicy: AllPassPenaltyPolicy
    public var zeroTricksAllPassPoolBonus: Int
    public var dealerTalonCompensation: DealerTalonCompensation
    /// Recording scales are deliberately separate. In Leningrad a made
    /// contract keeps the standard 2/4/6/8/10 pool value, while direct
    /// whists and declarer remise mountain entries are doubled.
    public var poolValueMultiplier: Int
    public var mountainValueMultiplier: Int
    public var whistValueMultiplier: Int

    /// Conversion rates used only when the pulka is reduced to a zero-sum
    /// final balance. Leningrad values one pool point at 20 whists while a
    /// recorded mountain point remains worth 10.
    public var poolPointWhistValue: Int
    public var mountainPointWhistValue: Int

    public init(
        allowSeniorHandHoldBid: Bool = true,
        requireWhistOnTenTrickContracts: Bool = false,
        forceWhistOnSixSpades: Bool = false,
        singleWhistScoring: SingleWhistScoring = .greedy,
        failedDeclarerConsolation: FailedDeclarerConsolation = .eachDefender,
        whistResponsibility: WhistResponsibility = .responsible,
        allPassTalonPolicy: AllPassTalonPolicy = .classic,
        allPassPenaltyPolicy: AllPassPenaltyPolicy = .perTrick(multiplier: 1, amnesty: true),
        zeroTricksAllPassPoolBonus: Int = 1,
        dealerTalonCompensation: DealerTalonCompensation = .classic,
        poolValueMultiplier: Int = 1,
        mountainValueMultiplier: Int = 1,
        whistValueMultiplier: Int = 1,
        poolPointWhistValue: Int = 10,
        mountainPointWhistValue: Int = 10
    ) {
        precondition(zeroTricksAllPassPoolBonus >= 0, "zeroTricksAllPassPoolBonus cannot be negative.")
        precondition(poolValueMultiplier > 0, "poolValueMultiplier must be positive.")
        precondition(mountainValueMultiplier > 0, "mountainValueMultiplier must be positive.")
        precondition(whistValueMultiplier > 0, "whistValueMultiplier must be positive.")
        precondition(poolPointWhistValue > 0, "poolPointWhistValue must be positive.")
        precondition(mountainPointWhistValue > 0, "mountainPointWhistValue must be positive.")
        self.allowSeniorHandHoldBid = allowSeniorHandHoldBid
        self.requireWhistOnTenTrickContracts = requireWhistOnTenTrickContracts
        self.forceWhistOnSixSpades = forceWhistOnSixSpades
        self.singleWhistScoring = singleWhistScoring
        self.failedDeclarerConsolation = failedDeclarerConsolation
        self.whistResponsibility = whistResponsibility
        self.allPassTalonPolicy = allPassTalonPolicy
        self.allPassPenaltyPolicy = allPassPenaltyPolicy
        self.zeroTricksAllPassPoolBonus = zeroTricksAllPassPoolBonus
        self.dealerTalonCompensation = dealerTalonCompensation
        self.poolValueMultiplier = poolValueMultiplier
        self.mountainValueMultiplier = mountainValueMultiplier
        self.whistValueMultiplier = whistValueMultiplier
        self.poolPointWhistValue = poolPointWhistValue
        self.mountainPointWhistValue = mountainPointWhistValue
    }

    /// A single validation source for engine construction, snapshot
    /// rehydration, and defensive decoding of persisted multiplayer state.
    /// Public properties remain mutable for table configuration, so checking
    /// only the initializer is not sufficient.
    var configurationError: String? {
        if zeroTricksAllPassPoolBonus < 0 {
            return "Zero-trick raspasy pool bonus cannot be negative."
        }
        let positiveValues: [(name: String, value: Int)] = [
            ("Pool value multiplier", poolValueMultiplier),
            ("Mountain value multiplier", mountainValueMultiplier),
            ("Whist value multiplier", whistValueMultiplier),
            ("Pool-point whist value", poolPointWhistValue),
            ("Mountain-point whist value", mountainPointWhistValue),
        ]
        if let invalid = positiveValues.first(where: { $0.value <= 0 }) {
            return "\(invalid.name) must be positive."
        }
        return nil
    }

    public static let sochi = PreferansRules()

    /// Compatibility name retained for fixtures written before talon-led
    /// raspasy became part of the canonical Sochi profile.
    public static let sochiWithTalonLedAllPass = PreferansRules.sochi

    /// Tournament-style Leningrad profile: pool entries keep the standard
    /// ladder, while mountain and direct-whist entries are doubled. Whist is
    /// semi-responsible and, on a declarer remise, a lone whister splits the
    /// defender-trick score with the passer.
    public static let leningrad = PreferansRules(
        requireWhistOnTenTrickContracts: true,
        singleWhistScoring: .gentleman,
        failedDeclarerConsolation: .eachDefender,
        whistResponsibility: .semiResponsible,
        allPassTalonPolicy: .classic,
        allPassPenaltyPolicy: .perTrick(multiplier: 2, amnesty: false),
        zeroTricksAllPassPoolBonus: 1,
        poolValueMultiplier: 1,
        mountainValueMultiplier: 2,
        whistValueMultiplier: 2,
        poolPointWhistValue: 20,
        mountainPointWhistValue: 10
    )

    public func whistRequirement(for contract: GameContract) -> Int {
        switch contract.tricks {
        case 6: return 4
        case 7: return 2
        case 8, 9: return 1
        case 10: return requireWhistOnTenTrickContracts ? 1 : 0
        default: return 0
        }
    }

    private enum CodingKeys: String, CodingKey {
        case allowSeniorHandHoldBid
        case requireWhistOnTenTrickContracts
        case forceWhistOnSixSpades
        case singleWhistScoring
        case failedDeclarerConsolation
        case whistResponsibility
        case allPassTalonPolicy
        case allPassPenaltyPolicy
        case zeroTricksAllPassPoolBonus
        case dealerTalonCompensation
        case poolValueMultiplier
        case mountainValueMultiplier
        case whistValueMultiplier
        case poolPointWhistValue
        case mountainPointWhistValue
        /// Legacy snapshots used one multiplier for every score column.
        case scoringMultiplier
    }

    /// Decode old snapshots without crashing. A legacy single multiplier is
    /// applied to all three recording columns, preserving the behavior that
    /// snapshot was created under; new profiles encode the independent scales.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let legacyMultiplier = try values.decodeIfPresent(Int.self, forKey: .scoringMultiplier)
        let zeroTricksAllPassPoolBonus = try values.decode(Int.self, forKey: .zeroTricksAllPassPoolBonus)
        let poolValueMultiplier = try values.decodeIfPresent(Int.self, forKey: .poolValueMultiplier)
            ?? legacyMultiplier ?? 1
        let mountainValueMultiplier = try values.decodeIfPresent(Int.self, forKey: .mountainValueMultiplier)
            ?? legacyMultiplier ?? 1
        let whistValueMultiplier = try values.decodeIfPresent(Int.self, forKey: .whistValueMultiplier)
            ?? legacyMultiplier ?? 1
        let poolPointWhistValue = try values.decodeIfPresent(Int.self, forKey: .poolPointWhistValue) ?? 10
        let mountainPointWhistValue = try values.decodeIfPresent(Int.self, forKey: .mountainPointWhistValue) ?? 10

        // Validate before calling the programmer-facing initializer: its
        // preconditions are appropriate for source mistakes but persisted
        // network data must fail as a normal decoding error, never trap.
        var decoded = PreferansRules.sochi
        decoded.zeroTricksAllPassPoolBonus = zeroTricksAllPassPoolBonus
        decoded.poolValueMultiplier = poolValueMultiplier
        decoded.mountainValueMultiplier = mountainValueMultiplier
        decoded.whistValueMultiplier = whistValueMultiplier
        decoded.poolPointWhistValue = poolPointWhistValue
        decoded.mountainPointWhistValue = mountainPointWhistValue
        if let error = decoded.configurationError {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: error
            ))
        }

        self.init(
            allowSeniorHandHoldBid: try values.decode(Bool.self, forKey: .allowSeniorHandHoldBid),
            requireWhistOnTenTrickContracts: try values.decode(Bool.self, forKey: .requireWhistOnTenTrickContracts),
            forceWhistOnSixSpades: try values.decodeIfPresent(Bool.self, forKey: .forceWhistOnSixSpades) ?? false,
            singleWhistScoring: try values.decode(SingleWhistScoring.self, forKey: .singleWhistScoring),
            failedDeclarerConsolation: try values.decode(FailedDeclarerConsolation.self, forKey: .failedDeclarerConsolation),
            whistResponsibility: try values.decode(WhistResponsibility.self, forKey: .whistResponsibility),
            allPassTalonPolicy: try values.decode(AllPassTalonPolicy.self, forKey: .allPassTalonPolicy),
            allPassPenaltyPolicy: try values.decode(AllPassPenaltyPolicy.self, forKey: .allPassPenaltyPolicy),
            zeroTricksAllPassPoolBonus: zeroTricksAllPassPoolBonus,
            dealerTalonCompensation: try values.decodeIfPresent(
                DealerTalonCompensation.self,
                forKey: .dealerTalonCompensation
            ) ?? .classic,
            poolValueMultiplier: poolValueMultiplier,
            mountainValueMultiplier: mountainValueMultiplier,
            whistValueMultiplier: whistValueMultiplier,
            poolPointWhistValue: poolPointWhistValue,
            mountainPointWhistValue: mountainPointWhistValue
        )
    }

    /// Keep the default Sochi wire format compact. Non-default profiles carry
    /// only the recording/conversion values that differ from one/ten.
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(allowSeniorHandHoldBid, forKey: .allowSeniorHandHoldBid)
        try values.encode(requireWhistOnTenTrickContracts, forKey: .requireWhistOnTenTrickContracts)
        if forceWhistOnSixSpades {
            try values.encode(true, forKey: .forceWhistOnSixSpades)
        }
        try values.encode(singleWhistScoring, forKey: .singleWhistScoring)
        try values.encode(failedDeclarerConsolation, forKey: .failedDeclarerConsolation)
        try values.encode(whistResponsibility, forKey: .whistResponsibility)
        try values.encode(allPassTalonPolicy, forKey: .allPassTalonPolicy)
        try values.encode(allPassPenaltyPolicy, forKey: .allPassPenaltyPolicy)
        try values.encode(zeroTricksAllPassPoolBonus, forKey: .zeroTricksAllPassPoolBonus)
        if dealerTalonCompensation != .classic {
            try values.encode(dealerTalonCompensation, forKey: .dealerTalonCompensation)
        }
        if poolValueMultiplier != 1 { try values.encode(poolValueMultiplier, forKey: .poolValueMultiplier) }
        if mountainValueMultiplier != 1 { try values.encode(mountainValueMultiplier, forKey: .mountainValueMultiplier) }
        if whistValueMultiplier != 1 { try values.encode(whistValueMultiplier, forKey: .whistValueMultiplier) }
        if poolPointWhistValue != 10 { try values.encode(poolPointWhistValue, forKey: .poolPointWhistValue) }
        if mountainPointWhistValue != 10 { try values.encode(mountainPointWhistValue, forKey: .mountainPointWhistValue) }
    }
}
