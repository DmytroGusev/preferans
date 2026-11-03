import Combine
import CryptoKit
import Foundation
import PreferansEngine

enum AnalyticsChoice: String { case unknown, allowed, denied }
enum AnalyticsMode: String { case local, online }
enum AnalyticsOperation: String { case create, join, resume, add, change, remove, ready, unready }
enum AnalyticsOutcome: String { case requested, succeeded, failed }
enum AnalyticsScreen: String { case lobby, settings, localTable = "local_table", onlineWaiting = "online_waiting", onlineTable = "online_table" }
enum AnalyticsConnection: String { case connected, reconnecting, takenOver = "taken_over", abandoned, seatLost = "seat_lost", serverError = "server_error" }
enum AnalyticsDeal: String {
    case game, misere, allPass = "all_pass", passedOut = "passed_out", concession, halfWhist = "half_whist"
    init(_ kind: DealResultKind) {
        switch kind {
        case .game: self = .game
        case .misere: self = .misere
        case .allPass: self = .allPass
        case .passedOut: self = .passedOut
        case .withoutThree: self = .concession
        case .halfWhist: self = .halfWhist
        }
    }
}

struct AnalyticsGameContext: Equatable, Sendable {
    let mode: AnalyticsMode
    let players: Int
    let bots: Int
    let convention: String

    init(mode: AnalyticsMode, players: Int, bots: Int, rules: PreferansRules) {
        self.mode = mode
        self.players = min(4, max(3, players))
        self.bots = min(self.players, max(0, bots))
        convention = rules == .sochi ? "vienna" : rules == .leningrad ? "prague" : rules == .rostov ? "berlin" : "custom"
    }

    var parameters: [String: Any] {
        ["game_mode": mode.rawValue, "player_count": players, "bot_count": bots, "convention": convention]
    }
}

/// Only bounded counts and fixed enums cross this API. No arbitrary identity,
/// room code, card, score, URL, command, or error text can be logged.
enum AppAnalyticsEvent: Equatable, Sendable {
    case consentGranted
    case onboardingCompleted
    case screen(AnalyticsScreen)
    case localGameStarted(AnalyticsGameContext)
    case onlineRoom(AnalyticsOperation, AnalyticsOutcome)
    case botSeat(AnalyticsOperation, AnalyticsOutcome, BotDifficulty?)
    case readiness(Bool, AnalyticsOutcome)
    case connection(AnalyticsConnection)
    case matchStarted(AnalyticsGameContext)
    case dealCompleted(AnalyticsGameContext, AnalyticsDeal)
    case matchCompleted(AnalyticsGameContext, deals: Int)

    var name: String {
        switch self {
        case .consentGranted: "analytics_opt_in"
        case .onboardingCompleted: "onboarding_complete"
        case .screen: "screen_view"
        case .localGameStarted: "local_game_start"
        case .onlineRoom: "online_room_flow"
        case .botSeat: "bot_seat_change"
        case .readiness: "ready_change"
        case .connection: "online_connection"
        case .matchStarted: "match_start"
        case .dealCompleted: "deal_complete"
        case .matchCompleted: "match_complete"
        }
    }

    var parameters: [String: Any] {
        switch self {
        case .consentGranted, .onboardingCompleted: [:]
        case let .screen(screen): ["screen_name": screen.rawValue, "screen_class": "Preferans"]
        case let .localGameStarted(context), let .matchStarted(context): context.parameters
        case let .onlineRoom(operation, outcome): ["operation": operation.rawValue, "outcome": outcome.rawValue]
        case let .botSeat(operation, outcome, difficulty):
            ["operation": operation.rawValue, "outcome": outcome.rawValue, "difficulty": difficulty?.rawValue ?? "none"]
        case let .readiness(ready, outcome): ["operation": ready ? "ready" : "unready", "outcome": outcome.rawValue]
        case let .connection(state): ["connection_state": state.rawValue]
        case let .dealCompleted(context, kind): context.parameters.merging(["deal_kind": kind.rawValue]) { _, new in new }
        case let .matchCompleted(context, deals): context.parameters.merging(["deals_played": min(10000, max(0, deals))]) { _, new in new }
        }
    }
}

@MainActor
protocol AppAnalyticsSink: AnyObject {
    func enable() -> Bool
    func disableAndReset()
    func log(_ event: AppAnalyticsEvent)
}

@MainActor
final class AppAnalytics: ObservableObject {
    static let shared = AppAnalytics()
    static let choiceKey = "settings.analyticsConsent.v1"
    static let receiptKey = "settings.analyticsReceipts.v1"
    @Published private(set) var choice: AnalyticsChoice
    @Published private(set) var isOperational = false
    private let defaults: UserDefaults
    private let sink: (any AppAnalyticsSink)?
    private let automation: Bool
    private var receipts: [String]

    init(defaults: UserDefaults = .standard, sink: (any AppAnalyticsSink)? = nil, automation: Bool? = nil) {
        self.defaults = defaults
        choice = AnalyticsChoice(rawValue: defaults.string(forKey: Self.choiceKey) ?? "") ?? .unknown
        receipts = Array((defaults.stringArray(forKey: Self.receiptKey) ?? []).suffix(512))
        #if DEBUG
        let liveVerification = ProcessInfo.processInfo.arguments.contains("-analyticsLiveVerification")
        #else
        let liveVerification = false
        #endif
        self.automation = automation ?? (!liveVerification && (TestHarness.isUIAutomation() || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil))
        #if os(iOS) && canImport(FirebaseAnalytics)
        self.sink = sink ?? FirebaseAnalyticsSink()
        #else
        self.sink = sink
        #endif
    }

    var shouldAsk: Bool { choice == .unknown && !automation }

    func startIfAllowed() {
        guard !automation, choice == .allowed, !isOperational else { return }
        isOperational = sink?.enable() ?? false
    }

    func setAllowed(_ allowed: Bool) {
        let previous = choice
        choice = allowed ? .allowed : .denied
        defaults.set(choice.rawValue, forKey: Self.choiceKey)
        if allowed {
            startIfAllowed()
            if previous != .allowed { track(.consentGranted) }
        } else {
            sink?.disableAndReset()
            isOperational = false
            receipts = []
            defaults.removeObject(forKey: Self.receiptKey)
        }
    }

    func track(_ event: AppAnalyticsEvent) {
        guard isOperational, choice == .allowed, !automation else { return }
        sink?.log(event)
    }

    /// Table/revision identifiers are hashed and kept only on this device for
    /// reconnect deduplication. They are never parameters or Firebase user IDs.
    func trackOnce(_ event: AppAnalyticsEvent, table: UUID, revision: Int) {
        guard isOperational, choice == .allowed, !automation else { return }
        let key = SHA256.hash(data: Data("\(table.uuidString):\(revision):\(event.name)".utf8)).map { String(format: "%02x", $0) }.joined()
        guard !receipts.contains(key) else { return }
        track(event)
        receipts = Array((receipts + [key]).suffix(512))
        defaults.set(receipts, forKey: Self.receiptKey)
    }

    func recordGameEvents(_ events: [PreferansEvent], table: UUID, revision: Int, context: AnalyticsGameContext) {
        for event in events {
            switch event {
            case .dealStarted where revision == 1:
                trackOnce(.matchStarted(context), table: table, revision: revision)
            case let .dealScored(result):
                trackOnce(.dealCompleted(context, AnalyticsDeal(result.kind)), table: table, revision: revision)
            case let .matchEnded(summary):
                trackOnce(.matchCompleted(context, deals: summary.dealsPlayed), table: table, revision: revision)
            default: break
            }
        }
    }
}
