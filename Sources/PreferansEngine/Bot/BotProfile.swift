import Foundation

/// How deeply a bot searches hidden-card possibilities during play.
///
/// Difficulty changes computation and consistency, while temperament owns
/// risk-taking decisions. Keeping those axes separate makes bots feel
/// different without making an "expert" deliberately choose illegal or
/// obviously nonsensical moves.
public enum BotDifficulty: String, CaseIterable, Codable, Hashable, Sendable {
    case casual
    case seasoned
    case expert

    public var plannerSamples: Int {
        switch self {
        case .casual: 6
        case .seasoned: 16
        case .expert: 32
        }
    }

    /// Added to the bid affordability margin. Higher difficulty is willing to
    /// convert a thinner estimate into a live auction call, while casual play
    /// keeps a larger safety buffer.
    var bidMarginAdjustment: Double {
        switch self {
        case .casual: -0.25
        case .seasoned: 0
        case .expert: 0.25
        }
    }

    /// Penalty applied when a declared contract is estimated to fail. Stronger
    /// bots can price controlled risk instead of treating every undertrick as
    /// equally damaging; casual bots protect the score more aggressively.
    var contractFailurePenalty: Double {
        switch self {
        case .casual: 6
        case .seasoned: 5
        case .expert: 4
        }
    }

    /// Added to the clean-misère threshold used while opening the auction.
    var misereToleranceAdjustment: Double {
        switch self {
        case .casual: -0.15
        case .seasoned: 0
        case .expert: 0.15
        }
    }
}

/// A bot's appetite for taking responsibility in the auction and whist.
public enum BotTemperament: String, CaseIterable, Codable, Hashable, Sendable {
    case careful
    case adaptive
    case bold

    /// Added to the existing bid affordability margin. Positive values make
    /// borderline bids more likely; negative values demand more safety.
    var bidMarginAdjustment: Double {
        switch self {
        case .careful: -0.35
        case .adaptive: 0
        case .bold: 0.35
        }
    }

    /// Added to the expected-trick threshold for taking a whist.
    var whistThresholdAdjustment: Double {
        switch self {
        case .careful: 0.35
        case .adaptive: 0
        case .bold: -0.35
        }
    }

    var misereToleranceAdjustment: Double {
        switch self {
        case .careful: -0.25
        case .adaptive: 0
        case .bold: 0.25
        }
    }

    /// Applied to rollout standard deviation after the expected score is
    /// calculated. Careful bots prefer reliable lines, adaptive bots maximize
    /// expectation, and bold bots accept controlled variance for upside.
    var rolloutRiskWeight: Double {
        switch self {
        case .careful: -0.35
        case .adaptive: 0
        case .bold: 0.35
        }
    }
}

/// Stable, serializable configuration for one bot seat.
public struct BotProfile: Codable, Hashable, Sendable {
    public var difficulty: BotDifficulty
    public var temperament: BotTemperament

    public init(
        difficulty: BotDifficulty = .seasoned,
        temperament: BotTemperament = .adaptive
    ) {
        self.difficulty = difficulty
        self.temperament = temperament
    }

    public static let standard = BotProfile()
}
