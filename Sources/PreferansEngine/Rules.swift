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

    public enum WhistResponsibility: Hashable, Codable, Sendable {
        case responsible
        case semiResponsible
        /// Rostov replaces the (halved) whist-remise mountain entry with a
        /// direct payment of this many whists per mountain point to each
        /// opponent.
        case directWhists(pointsPerMountainPoint: Int)
        case none

        private enum CodingKeys: String, CodingKey {
            case directWhists
            case pointsPerMountainPoint
        }

        /// Keep the pre-Rostov wire format stable for the three existing
        /// policies. The associated Rostov policy uses a keyed payload so old
        /// snapshots and worker messages continue to decode unchanged.
        public init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer(),
               let raw = try? single.decode(String.self) {
                switch raw {
                case "responsible": self = .responsible
                case "semiResponsible": self = .semiResponsible
                case "none": self = .none
                default:
                    throw DecodingError.dataCorrupted(.init(
                        codingPath: decoder.codingPath,
                        debugDescription: "Unknown whist responsibility: \(raw)"
                    ))
                }
                return
            }

            let values = try decoder.container(keyedBy: CodingKeys.self)
            if values.contains(.directWhists) {
                let nested = try values.nestedContainer(keyedBy: CodingKeys.self, forKey: .directWhists)
                self = .directWhists(
                    pointsPerMountainPoint: try nested.decode(Int.self, forKey: .pointsPerMountainPoint)
                )
                return
            }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid whist responsibility payload."
            ))
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .responsible:
                var single = encoder.singleValueContainer()
                try single.encode("responsible")
            case .semiResponsible:
                var single = encoder.singleValueContainer()
                try single.encode("semiResponsible")
            case .none:
                var single = encoder.singleValueContainer()
                try single.encode("none")
            case let .directWhists(pointsPerMountainPoint):
                var values = encoder.container(keyedBy: CodingKeys.self)
                var nested = values.nestedContainer(keyedBy: CodingKeys.self, forKey: .directWhists)
                try nested.encode(pointsPerMountainPoint, forKey: .pointsPerMountainPoint)
            }
        }
    }

    public enum DeclarerRemisePolicy: Hashable, Codable, Sendable {
        /// Canonical Sochi/Leningrad behavior: write mountain for each
        /// undertrick and apply the configured defender consolation.
        case mountainAndConsolation
        /// Rostov behavior: no mountain entry; each defender writes the
        /// configured fixed direct-whist consolation for every undertrick.
        case directWhistsPerDefender(whistsPerUndertrick: Int)
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
        /// Rostov raspasy: the lowest-trick player(s) write direct whists on
        /// the other players instead of receiving mountain entries.
        case directWhistsToLowest(pointsPerTrick: Int)
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
    /// Routes a ten-trick contract through the ordinary defender whist/pass
    /// decision. Despite the historical property name, this does not force a
    /// defender to whist; only the separate Stalingrad agreement does that.
    public var requireWhistOnTenTrickContracts: Bool
    /// Optional Stalingrad convention: both defenders must whist, with
    /// closed hands, against a six-spade contract. This is a table agreement,
    /// not an intrinsic part of either the Sochi or Leningrad profile.
    public var forceWhistOnSixSpades: Bool
    public var singleWhistScoring: SingleWhistScoring
    public var failedDeclarerConsolation: FailedDeclarerConsolation
    public var whistResponsibility: WhistResponsibility
    public var declarerRemisePolicy: DeclarerRemisePolicy
    public var allPassTalonPolicy: AllPassTalonPolicy
    /// Mountain penalty multiplier for each trick on an all-pass deal. This
    /// does not scale the separate clean-exit pool credit below.
    public var allPassPenaltyPolicy: AllPassPenaltyPolicy
    /// Pool points awarded to a player who takes zero tricks on an all-pass
    /// deal. The value follows the raspasy progression, not the mountain
    /// penalty multiplier (Leningrad records 1/2/3 in the pool while its
    /// trick penalties are 2/4/6 in the mountain).
    public var zeroTricksAllPassPoolBonus: Int
    public var dealerTalonCompensation: DealerTalonCompensation
    /// Recording scales are deliberately separate. In Leningrad a made
    /// contract keeps the standard 2/4/6/8/10 pool value, while direct
    /// whists and declarer remise mountain entries are doubled.
    public var poolValueMultiplier: Int
    public var mountainValueMultiplier: Int
    public var whistValueMultiplier: Int
    /// Optional divisor for ordinary whist recording. Canonical Sochi,
    /// Leningrad, and Rostov profiles all record ordinary trick whists at the
    /// contract's normal value; the explicit divisor remains available for a
    /// house convention that deliberately changes that scale.
    public var whistValueDivisor: Int

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
        declarerRemisePolicy: DeclarerRemisePolicy = .mountainAndConsolation,
        allPassTalonPolicy: AllPassTalonPolicy = .classic,
        // Canonical Sochi/Leningrad raspasy charge every trick in the
        // mountain.  Amnesty remains an explicit house-rule option, but it
        // must not be the production default.
        allPassPenaltyPolicy: AllPassPenaltyPolicy = .perTrick(multiplier: 1, amnesty: false),
        zeroTricksAllPassPoolBonus: Int = 1,
        dealerTalonCompensation: DealerTalonCompensation = .classic,
        poolValueMultiplier: Int = 1,
        mountainValueMultiplier: Int = 1,
        whistValueMultiplier: Int = 1,
        whistValueDivisor: Int = 1,
        poolPointWhistValue: Int = 10,
        mountainPointWhistValue: Int = 10
    ) {
        switch allPassPenaltyPolicy {
        case let .perTrick(multiplier, _):
            precondition(multiplier > 0, "allPassPenaltyPolicy multiplier must be positive.")
        case let .directWhistsToLowest(pointsPerTrick):
            precondition(pointsPerTrick > 0, "allPass direct-whist value must be positive.")
        }
        if case let .directWhists(pointsPerMountainPoint) = whistResponsibility {
            precondition(pointsPerMountainPoint > 0, "whist direct-remise value must be positive.")
        }
        if case let .directWhistsPerDefender(whistsPerUndertrick) = declarerRemisePolicy {
            precondition(whistsPerUndertrick > 0, "declarer direct-remise value must be positive.")
        }
        precondition(zeroTricksAllPassPoolBonus >= 0, "zeroTricksAllPassPoolBonus cannot be negative.")
        precondition(poolValueMultiplier > 0, "poolValueMultiplier must be positive.")
        precondition(mountainValueMultiplier > 0, "mountainValueMultiplier must be positive.")
        precondition(whistValueMultiplier > 0, "whistValueMultiplier must be positive.")
        precondition(whistValueDivisor > 0, "whistValueDivisor must be positive.")
        precondition(
            [2, 4, 6, 8, 10].allSatisfy { $0.isMultiple(of: whistValueDivisor) },
            "whistValueDivisor must divide every contract value."
        )
        precondition(poolPointWhistValue > 0, "poolPointWhistValue must be positive.")
        precondition(mountainPointWhistValue > 0, "mountainPointWhistValue must be positive.")
        self.allowSeniorHandHoldBid = allowSeniorHandHoldBid
        self.requireWhistOnTenTrickContracts = requireWhistOnTenTrickContracts
        self.forceWhistOnSixSpades = forceWhistOnSixSpades
        self.singleWhistScoring = singleWhistScoring
        self.failedDeclarerConsolation = failedDeclarerConsolation
        self.whistResponsibility = whistResponsibility
        self.declarerRemisePolicy = declarerRemisePolicy
        self.allPassTalonPolicy = allPassTalonPolicy
        self.allPassPenaltyPolicy = allPassPenaltyPolicy
        self.zeroTricksAllPassPoolBonus = zeroTricksAllPassPoolBonus
        self.dealerTalonCompensation = dealerTalonCompensation
        self.poolValueMultiplier = poolValueMultiplier
        self.mountainValueMultiplier = mountainValueMultiplier
        self.whistValueMultiplier = whistValueMultiplier
        self.whistValueDivisor = whistValueDivisor
        self.poolPointWhistValue = poolPointWhistValue
        self.mountainPointWhistValue = mountainPointWhistValue
    }

    /// A single validation source for engine construction, snapshot
    /// rehydration, and defensive decoding of persisted multiplayer state.
    /// Public properties remain mutable for table configuration, so checking
    /// only the initializer is not sufficient.
    var configurationError: String? {
        switch allPassPenaltyPolicy {
        case let .perTrick(multiplier, _) where multiplier <= 0:
            return "All-pass penalty multiplier must be positive."
        case let .directWhistsToLowest(pointsPerTrick) where pointsPerTrick <= 0:
            return "All-pass direct-whist value must be positive."
        default:
            break
        }
        if case let .directWhists(pointsPerMountainPoint) = whistResponsibility,
           pointsPerMountainPoint <= 0 {
            return "Whist direct-remise value must be positive."
        }
        if case let .directWhistsPerDefender(whistsPerUndertrick) = declarerRemisePolicy,
           whistsPerUndertrick <= 0 {
            return "Declarer direct-remise value must be positive."
        }
        if zeroTricksAllPassPoolBonus < 0 {
            return "Zero-trick raspasy pool bonus cannot be negative."
        }
        let positiveValues: [(name: String, value: Int)] = [
            ("Pool value multiplier", poolValueMultiplier),
            ("Mountain value multiplier", mountainValueMultiplier),
            ("Whist value multiplier", whistValueMultiplier),
            ("Whist value divisor", whistValueDivisor),
            ("Pool-point whist value", poolPointWhistValue),
            ("Mountain-point whist value", mountainPointWhistValue),
        ]
        if let invalid = positiveValues.first(where: { $0.value <= 0 }) {
            return "\(invalid.name) must be positive."
        }
        if [2, 4, 6, 8, 10].contains(where: { !$0.isMultiple(of: whistValueDivisor) }) {
            return "Whist value divisor must divide every contract value."
        }
        return nil
    }

    public static let sochi = PreferansRules()

    /// Stalingrad is the explicit six-spades forced-defense convention. It
    /// keeps the Sochi scoring and raspasy rules; only the whist decision for
    /// 6♠ changes. Keeping it as a named profile prevents the lobby from
    /// silently reconstructing a subtly different set of rules.
    public static let stalingrad = PreferansRules(forceWhistOnSixSpades: true)

    /// Rostov/Moscow scoring: ordinary trick whists keep the standard
    /// contract value, whist-remise penalties are half-responsible and paid
    /// as direct five-whist payments, and raspasy is fixed-price with the
    /// talon kept hidden.
    public static let rostov = PreferansRules(
        singleWhistScoring: .greedy,
        failedDeclarerConsolation: .none,
        whistResponsibility: .directWhists(pointsPerMountainPoint: 5),
        declarerRemisePolicy: .directWhistsPerDefender(whistsPerUndertrick: 10),
        allPassTalonPolicy: .ignored,
        allPassPenaltyPolicy: .directWhistsToLowest(pointsPerTrick: 5),
        zeroTricksAllPassPoolBonus: 1,
        poolValueMultiplier: 1,
        mountainValueMultiplier: 1,
        whistValueMultiplier: 1,
        whistValueDivisor: 1,
        poolPointWhistValue: 10,
        mountainPointWhistValue: 10
    )

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

    /// Recorded whists for one defender trick under this convention. The
    /// canonical contract ladder is 2/4/6/8/10 in every production profile.
    public func recordedWhistValue(for contract: GameContract) -> Int {
        contract.value * whistValueMultiplier / whistValueDivisor
    }

    private enum CodingKeys: String, CodingKey {
        case allowSeniorHandHoldBid
        case requireWhistOnTenTrickContracts
        case forceWhistOnSixSpades
        case singleWhistScoring
        case failedDeclarerConsolation
        case whistResponsibility
        case declarerRemisePolicy
        case allPassTalonPolicy
        case allPassPenaltyPolicy
        case zeroTricksAllPassPoolBonus
        case dealerTalonCompensation
        case poolValueMultiplier
        case mountainValueMultiplier
        case whistValueMultiplier
        case whistValueDivisor
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
        let allPassPenaltyPolicy = try values.decode(AllPassPenaltyPolicy.self, forKey: .allPassPenaltyPolicy)
        let zeroTricksAllPassPoolBonus = try values.decode(Int.self, forKey: .zeroTricksAllPassPoolBonus)
        let poolValueMultiplier = try values.decodeIfPresent(Int.self, forKey: .poolValueMultiplier)
            ?? legacyMultiplier ?? 1
        let mountainValueMultiplier = try values.decodeIfPresent(Int.self, forKey: .mountainValueMultiplier)
            ?? legacyMultiplier ?? 1
        let whistValueMultiplier = try values.decodeIfPresent(Int.self, forKey: .whistValueMultiplier)
            ?? legacyMultiplier ?? 1
        let whistValueDivisor = try values.decodeIfPresent(Int.self, forKey: .whistValueDivisor) ?? 1
        let poolPointWhistValue = try values.decodeIfPresent(Int.self, forKey: .poolPointWhistValue) ?? 10
        let mountainPointWhistValue = try values.decodeIfPresent(Int.self, forKey: .mountainPointWhistValue) ?? 10

        // Validate before calling the programmer-facing initializer: its
        // preconditions are appropriate for source mistakes but persisted
        // network data must fail as a normal decoding error, never trap.
        var decoded = PreferansRules.sochi
        decoded.whistResponsibility = try values.decode(WhistResponsibility.self, forKey: .whistResponsibility)
        decoded.declarerRemisePolicy = try values.decodeIfPresent(
            DeclarerRemisePolicy.self,
            forKey: .declarerRemisePolicy
        ) ?? .mountainAndConsolation
        decoded.allPassPenaltyPolicy = allPassPenaltyPolicy
        decoded.zeroTricksAllPassPoolBonus = zeroTricksAllPassPoolBonus
        decoded.poolValueMultiplier = poolValueMultiplier
        decoded.mountainValueMultiplier = mountainValueMultiplier
        decoded.whistValueMultiplier = whistValueMultiplier
        decoded.whistValueDivisor = whistValueDivisor
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
            declarerRemisePolicy: try values.decodeIfPresent(
                DeclarerRemisePolicy.self,
                forKey: .declarerRemisePolicy
            ) ?? .mountainAndConsolation,
            allPassTalonPolicy: try values.decode(AllPassTalonPolicy.self, forKey: .allPassTalonPolicy),
            allPassPenaltyPolicy: allPassPenaltyPolicy,
            zeroTricksAllPassPoolBonus: zeroTricksAllPassPoolBonus,
            dealerTalonCompensation: try values.decodeIfPresent(
                DealerTalonCompensation.self,
                forKey: .dealerTalonCompensation
            ) ?? .classic,
            poolValueMultiplier: poolValueMultiplier,
            mountainValueMultiplier: mountainValueMultiplier,
            whistValueMultiplier: whistValueMultiplier,
            whistValueDivisor: whistValueDivisor,
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
        if declarerRemisePolicy != .mountainAndConsolation {
            try values.encode(declarerRemisePolicy, forKey: .declarerRemisePolicy)
        }
        try values.encode(allPassTalonPolicy, forKey: .allPassTalonPolicy)
        try values.encode(allPassPenaltyPolicy, forKey: .allPassPenaltyPolicy)
        try values.encode(zeroTricksAllPassPoolBonus, forKey: .zeroTricksAllPassPoolBonus)
        if dealerTalonCompensation != .classic {
            try values.encode(dealerTalonCompensation, forKey: .dealerTalonCompensation)
        }
        if poolValueMultiplier != 1 { try values.encode(poolValueMultiplier, forKey: .poolValueMultiplier) }
        if mountainValueMultiplier != 1 { try values.encode(mountainValueMultiplier, forKey: .mountainValueMultiplier) }
        if whistValueMultiplier != 1 { try values.encode(whistValueMultiplier, forKey: .whistValueMultiplier) }
        if whistValueDivisor != 1 { try values.encode(whistValueDivisor, forKey: .whistValueDivisor) }
        if poolPointWhistValue != 10 { try values.encode(poolPointWhistValue, forKey: .poolPointWhistValue) }
        if mountainPointWhistValue != 10 { try values.encode(mountainPointWhistValue, forKey: .mountainPointWhistValue) }
    }
}
