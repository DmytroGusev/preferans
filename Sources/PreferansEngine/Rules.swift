import Foundation

public struct PreferansRules: Hashable, Codable, Sendable {
    public enum SingleWhistScoring: String, Codable, Sendable {
        case greedy
        case ownHandOnly
        /// The lone whister and their passing partner split both the
        /// defender-trick whists and declarer-remise consolation equally.
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
        case leadSuitOnly
    }

    public enum AllPassPenaltyPolicy: Hashable, Codable, Sendable {
        case perTrick(multiplier: Int, amnesty: Bool)
    }

    public var allowSeniorHandHoldBid: Bool
    public var requireWhistOnTenTrickContracts: Bool
    public var singleWhistScoring: SingleWhistScoring
    public var failedDeclarerConsolation: FailedDeclarerConsolation
    public var whistResponsibility: WhistResponsibility
    public var allPassTalonPolicy: AllPassTalonPolicy
    public var allPassPenaltyPolicy: AllPassPenaltyPolicy
    public var zeroTricksAllPassPoolBonus: Int
    /// Multiplies contract, misere, whist and mountain values. The base
    /// ladder remains 2/4/6/8/10, while Leningrad uses double values.
    public var scoringMultiplier: Int

    public init(
        allowSeniorHandHoldBid: Bool = true,
        requireWhistOnTenTrickContracts: Bool = false,
        singleWhistScoring: SingleWhistScoring = .greedy,
        failedDeclarerConsolation: FailedDeclarerConsolation = .eachDefender,
        whistResponsibility: WhistResponsibility = .responsible,
        allPassTalonPolicy: AllPassTalonPolicy = .ignored,
        allPassPenaltyPolicy: AllPassPenaltyPolicy = .perTrick(multiplier: 1, amnesty: false),
        zeroTricksAllPassPoolBonus: Int = 1,
        scoringMultiplier: Int = 1
    ) {
        precondition(scoringMultiplier > 0, "scoringMultiplier must be positive.")
        self.allowSeniorHandHoldBid = allowSeniorHandHoldBid
        self.requireWhistOnTenTrickContracts = requireWhistOnTenTrickContracts
        self.singleWhistScoring = singleWhistScoring
        self.failedDeclarerConsolation = failedDeclarerConsolation
        self.whistResponsibility = whistResponsibility
        self.allPassTalonPolicy = allPassTalonPolicy
        self.allPassPenaltyPolicy = allPassPenaltyPolicy
        self.zeroTricksAllPassPoolBonus = zeroTricksAllPassPoolBonus
        self.scoringMultiplier = scoringMultiplier
    }

    public static let sochi = PreferansRules()

    public static let sochiWithTalonLedAllPass = PreferansRules(
        allPassTalonPolicy: .leadSuitOnly
    )

    /// Tournament-style Leningrad profile: all contract values are doubled,
    /// the whist is semi-responsible, and a lone whister splits the score
    /// with the defender who passed.
    public static let leningrad = PreferansRules(
        requireWhistOnTenTrickContracts: true,
        singleWhistScoring: .gentleman,
        failedDeclarerConsolation: .eachDefender,
        whistResponsibility: .semiResponsible,
        allPassPenaltyPolicy: .perTrick(multiplier: 2, amnesty: false),
        zeroTricksAllPassPoolBonus: 0,
        scoringMultiplier: 2
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
        case singleWhistScoring
        case failedDeclarerConsolation
        case whistResponsibility
        case allPassTalonPolicy
        case allPassPenaltyPolicy
        case zeroTricksAllPassPoolBonus
        case scoringMultiplier
    }

    /// Old online snapshots predate `scoringMultiplier`; decoding them as
    /// one preserves their original Sochi value scale.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            allowSeniorHandHoldBid: try values.decode(Bool.self, forKey: .allowSeniorHandHoldBid),
            requireWhistOnTenTrickContracts: try values.decode(Bool.self, forKey: .requireWhistOnTenTrickContracts),
            singleWhistScoring: try values.decode(SingleWhistScoring.self, forKey: .singleWhistScoring),
            failedDeclarerConsolation: try values.decode(FailedDeclarerConsolation.self, forKey: .failedDeclarerConsolation),
            whistResponsibility: try values.decode(WhistResponsibility.self, forKey: .whistResponsibility),
            allPassTalonPolicy: try values.decode(AllPassTalonPolicy.self, forKey: .allPassTalonPolicy),
            allPassPenaltyPolicy: try values.decode(AllPassPenaltyPolicy.self, forKey: .allPassPenaltyPolicy),
            zeroTricksAllPassPoolBonus: try values.decode(Int.self, forKey: .zeroTricksAllPassPoolBonus),
            scoringMultiplier: try values.decodeIfPresent(Int.self, forKey: .scoringMultiplier) ?? 1
        )
    }

    /// Keep the default Sochi wire format stable for existing room snapshots.
    /// Non-default profiles (for example, Leningrad) carry their multiplier.
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(allowSeniorHandHoldBid, forKey: .allowSeniorHandHoldBid)
        try values.encode(requireWhistOnTenTrickContracts, forKey: .requireWhistOnTenTrickContracts)
        try values.encode(singleWhistScoring, forKey: .singleWhistScoring)
        try values.encode(failedDeclarerConsolation, forKey: .failedDeclarerConsolation)
        try values.encode(whistResponsibility, forKey: .whistResponsibility)
        try values.encode(allPassTalonPolicy, forKey: .allPassTalonPolicy)
        try values.encode(allPassPenaltyPolicy, forKey: .allPassPenaltyPolicy)
        try values.encode(zeroTricksAllPassPoolBonus, forKey: .zeroTricksAllPassPoolBonus)
        if scoringMultiplier != 1 {
            try values.encode(scoringMultiplier, forKey: .scoringMultiplier)
        }
    }
}
