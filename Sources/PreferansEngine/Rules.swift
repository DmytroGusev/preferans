import Foundation

public struct PreferansRules: Hashable, Codable, Sendable {
    public enum SingleWhistScoring: String, Codable, Sendable {
        case greedy
        case ownHandOnly
    }

    public enum FailedDeclarerConsolation: String, Codable, Sendable {
        case none
        case eachDefender
    }

    public enum WhistResponsibility: String, Codable, Sendable {
        case responsible
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

    public init(
        allowSeniorHandHoldBid: Bool = true,
        requireWhistOnTenTrickContracts: Bool = false,
        singleWhistScoring: SingleWhistScoring = .greedy,
        failedDeclarerConsolation: FailedDeclarerConsolation = .eachDefender,
        whistResponsibility: WhistResponsibility = .responsible,
        allPassTalonPolicy: AllPassTalonPolicy = .ignored,
        allPassPenaltyPolicy: AllPassPenaltyPolicy = .perTrick(multiplier: 1, amnesty: false),
        zeroTricksAllPassPoolBonus: Int = 1
    ) {
        self.allowSeniorHandHoldBid = allowSeniorHandHoldBid
        self.requireWhistOnTenTrickContracts = requireWhistOnTenTrickContracts
        self.singleWhistScoring = singleWhistScoring
        self.failedDeclarerConsolation = failedDeclarerConsolation
        self.whistResponsibility = whistResponsibility
        self.allPassTalonPolicy = allPassTalonPolicy
        self.allPassPenaltyPolicy = allPassPenaltyPolicy
        self.zeroTricksAllPassPoolBonus = zeroTricksAllPassPoolBonus
    }

    public static let sochi = PreferansRules()

    public static let sochiWithTalonLedAllPass = PreferansRules(
        allPassTalonPolicy: .leadSuitOnly
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
}
