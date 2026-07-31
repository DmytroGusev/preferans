import Foundation
import PreferansEngine
import SwiftUI

public enum PreferansVariant: String, CaseIterable, Identifiable, Equatable, Codable {
    case odesa
    case wien

    public var id: String { rawValue }

    public var title: LocalizedStringKey {
        switch self {
        case .odesa: return "variant.odesa.title"
        case .wien:  return "variant.wien.title"
        }
    }

    public var standardName: LocalizedStringKey {
        switch self {
        case .odesa: return "variant.odesa.standard"
        case .wien:  return "variant.wien.standard"
        }
    }

    public var summary: LocalizedStringKey {
        switch self {
        case .odesa: return "variant.odesa.summary"
        case .wien:  return "variant.wien.summary"
        }
    }

    public var rules: PreferansRules {
        switch self {
        case .odesa:
            return .sochi
        case .wien:
            return .leningrad
        }
    }

    public var poolClosure: PoolClosurePolicy {
        switch self {
        case .odesa:
            return .individualWithAmericanAid
        case .wien:
            return .tableTotal
        }
    }

    public var raspasy: RaspasyPolicy {
        switch self {
        case .odesa:
            return .sochi
        case .wien:
            return .leningrad
        }
    }
}

public enum PulkaLimit: String, CaseIterable, Identifiable, Equatable, Codable {
    case short = "11"
    case standard = "21"
    case custom = "custom"

    public static let defaultCustomTarget = 21
    public static let customRange = 1...999
    public static let defaultCustomTableTarget = 63
    public static let customTableRange = 1...3_996

    public var id: String { rawValue }

    public var target: Int {
        switch self {
        case .short: return 11
        case .standard: return 21
        case .custom: return Self.defaultCustomTarget
        }
    }

    public func target(custom: Int) -> Int {
        switch self {
        case .short, .standard:
            return target
        case .custom:
            return min(max(custom, Self.customRange.lowerBound), Self.customRange.upperBound)
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .short: return "11"
        case .standard: return "21"
        case .custom: return "Custom"
        }
    }
}

public enum BotMoveSpeed: String, CaseIterable, Identifiable, Equatable {
    case instant
    case normal
    case slow

    public var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .instant: return "Instant"
        case .normal:  return "Normal"
        case .slow:    return "Slow"
        }
    }

    public var delay: Duration {
        switch self {
        case .instant: return BotPacing.instant
        case .normal:  return .milliseconds(1200)
        case .slow:    return .milliseconds(2200)
        }
    }
}

extension BotDifficulty {
    var label: LocalizedStringKey {
        switch self {
        case .casual: "Casual"
        case .seasoned: "Seasoned"
        case .expert: "Expert"
        }
    }
}

extension BotTemperament {
    var label: LocalizedStringKey {
        switch self {
        case .careful: "Careful"
        case .adaptive: "Adaptive"
        case .bold: "Bold"
        }
    }
}

extension BotDecisionRationale {
    var label: LocalizedStringKey {
        switch self {
        case .auctionPass: "bot.insight.auctionPass"
        case .gameBid: "bot.insight.gameBid"
        case .misereBid: "bot.insight.misereBid"
        case .totusBid: "bot.insight.totusBid"
        case .contractFit: "bot.insight.contractFit"
        case .contractConcession: "bot.insight.contractConcession"
        case .discardForContract: "bot.insight.discardForContract"
        case .discardForMisere: "bot.insight.discardForMisere"
        case .fullWhist: "bot.insight.fullWhist"
        case .halfWhist: "bot.insight.halfWhist"
        case .defensivePass: "bot.insight.defensivePass"
        case .openDefense: "bot.insight.openDefense"
        case .closedDefense: "bot.insight.closedDefense"
        case .forcedSettlement: "bot.insight.forcedSettlement"
        case .contestSettlement: "bot.insight.contestSettlement"
        }
    }
}

public struct RegisteredOnlineAccount: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var provider: OnlineAccountProvider
    public var accountID: String
    public var displayName: String

    public init(
        schemaVersion: Int = AppIdentifiers.cloudSchemaVersion,
        provider: OnlineAccountProvider,
        accountID: String,
        displayName: String
    ) {
        self.schemaVersion = schemaVersion
        self.provider = provider
        self.accountID = accountID
        self.displayName = displayName
    }
}

/// Single seat in the lobby's local-table roster. Folds the seat's
/// human/bot kind into the same struct as its name so the two can never drift.
public struct LobbySeat: Identifiable, Equatable {
    public enum Kind: Equatable {
        case human
        case bot(BotProfile)
    }

    public let id: UUID
    public var name: String
    public var kind: Kind

    public init(id: UUID = UUID(), name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    public var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isBot: Bool {
        if case .bot = kind { return true }
        return false
    }

    public var botProfile: BotProfile? {
        guard case let .bot(profile) = kind else { return nil }
        return profile
    }

    public mutating func setBotProfile(_ profile: BotProfile) {
        guard isBot else { return }
        kind = .bot(profile)
    }
}

extension LobbySeat {
    /// Stock seat names used for fresh rosters. The "you" pill on the
    /// viewer's seat already marks the human, so seat 0 carries a real name.
    static let defaultNames = ["Neo", "Morpheus", "Trinity", "Agent Smith"]

    static func defaults(count: Int) -> [LobbySeat] {
        precondition(count >= 3 && count <= 4, "Preferans only supports 3- or 4-player tables.")
        return (0..<count).map { index in
            LobbySeat(
                name: defaultNames[index],
                kind: index == 0 ? .human : .bot(stockBotProfile(for: defaultNames[index]))
            )
        }
    }

    static func quickPlayVsBots() -> [LobbySeat] {
        defaults(count: 3)
    }

    static func demoBots(count: Int) -> [LobbySeat] {
        defaults(count: count).map { seat in
            LobbySeat(id: seat.id, name: seat.name, kind: .bot(stockBotProfile(for: seat.name)))
        }
    }

    static func resize(_ existing: [LobbySeat], to count: Int) -> [LobbySeat] {
        precondition(count >= 3 && count <= 4, "Preferans only supports 3- or 4-player tables.")
        if existing.count == count { return existing }
        if count < existing.count {
            return Array(existing.prefix(count))
        }
        var resized = existing
        while resized.count < count {
            resized = addBot(to: resized)
        }
        return resized
    }

    static func addBot(to existing: [LobbySeat]) -> [LobbySeat] {
        var resized = existing
        let name = nextBotName(existing: existing)
        resized.append(LobbySeat(name: name, kind: .bot(stockBotProfile(for: name))))
        return resized
    }

    private static func stockBotProfile(for name: String) -> BotProfile {
        switch name {
        case "Morpheus":
            return BotProfile(difficulty: .expert, temperament: .careful)
        case "Trinity":
            return BotProfile(difficulty: .seasoned, temperament: .bold)
        case "Agent Smith":
            return BotProfile(difficulty: .expert, temperament: .adaptive)
        case "Neo":
            return BotProfile(difficulty: .seasoned, temperament: .adaptive)
        default:
            return BotProfile(difficulty: .casual, temperament: .adaptive)
        }
    }

    private static func nextBotName(existing: [LobbySeat]) -> String {
        let usedNames = Set(existing.map(\.trimmedName))
        if let defaultName = defaultNames.dropFirst().first(where: { !usedNames.contains($0) }) {
            return defaultName
        }
        var suffix = existing.count + 1
        while usedNames.contains("Bot \(suffix)") {
            suffix += 1
        }
        return "Bot \(suffix)"
    }
}

extension Array where Element == LobbySeat {
    var rosterSummary: String {
        let bots = filter(\.isBot).count
        let humans = count - bots
        let humanLabel: String = humans == 1
            ? String(localized: "1 human")
            : String(localized: "\(humans) humans")
        let botLabel: String = bots == 1
            ? String(localized: "1 bot")
            : String(localized: "\(bots) bots")
        return "\(humanLabel) · \(botLabel)"
    }

    var validationError: String? {
        let names = map(\.trimmedName)
        if names.contains(where: \.isEmpty) {
            return String(localized: "Every seat needs a name.")
        }
        if Set(names).count != names.count {
            return String(localized: "Names must be unique.")
        }
        return nil
    }
}

/// One seat in the *online* table's composition. Separate from `LobbySeat`
/// (which configures the local bot game): an online seat is either you (the
/// host), an open seat you'll invite a friend to, or a bot the host drives.
public struct OnlineSeatSlot: Identifiable, Equatable {
    public enum Kind: String, Equatable, CaseIterable, Identifiable {
        case you, invite, bot
        public var id: String { rawValue }
    }

    public let id: UUID
    public var kind: Kind

    public init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }
}

extension OnlineSeatSlot {
    /// Canonical seat IDs for an online table. Display names ride on
    /// `PlayerIdentity`, so these compass IDs stay invisible to the player —
    /// they exist only so two fresh installs don't collide on a name.
    static func canonicalPlayerIDs(count: Int) -> [PlayerID] {
        let pool = ["north", "east", "south", "west"]
        let clamped = min(max(count, 3), 4)
        return (0..<clamped).map { PlayerID(pool[$0]) }
    }

    /// Fresh composition: you + open invite seats. The host opens invite seats
    /// by default and can flip any of them to a bot.
    static func defaultComposition(count: Int) -> [OnlineSeatSlot] {
        let clamped = min(max(count, 3), 4)
        return (0..<clamped).map { OnlineSeatSlot(kind: $0 == 0 ? .you : .invite) }
    }

    static func resize(_ existing: [OnlineSeatSlot], to count: Int) -> [OnlineSeatSlot] {
        let clamped = min(max(count, 3), 4)
        if existing.count == clamped { return existing }
        if clamped < existing.count { return Array(existing.prefix(clamped)) }
        var resized = existing
        while resized.count < clamped {
            resized.append(OnlineSeatSlot(kind: .invite))
        }
        return resized
    }
}

extension Array where Element == OnlineSeatSlot {
    var inviteCount: Int { filter { $0.kind == .invite }.count }
    var botCount: Int { filter { $0.kind == .bot }.count }
}
