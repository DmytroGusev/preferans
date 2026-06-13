import Dependencies
import SwiftUI
import PreferansEngine

@MainActor
public final class LobbyViewModel: ObservableObject {
    /// Which path the lobby is showing. The two flows no longer share a roster:
    /// `.local` configures a solo-vs-bots table; `.online` configures an online
    /// room with its own identity + seat composition.
    public enum LobbyMode: String, CaseIterable, Identifiable, Equatable {
        case local, online
        public var id: String { rawValue }
    }

    @Published public var localModel: GameViewModel?
    @Published public var onlineSession: InMemoryOnlineGameSession?
    @Published public var cloudOnlineSession: CloudflareOnlineGameSession?
    @Published public var lobbyMode: LobbyMode = .local
    @Published public var seats: [LobbySeat] = LobbySeat.defaults(count: 3)
    @Published public var botSpeed: BotMoveSpeed = .normal
    @Published public var errorText: String?
    /// Non-error, informational status (e.g. "invite ready"). Rendered in the
    /// lobby's accent color, not the red error style — keeping success and
    /// failure visually distinct.
    @Published public var infoText: String?
    @Published public private(set) var registeredOnlineAccount: RegisteredOnlineAccount?
    @Published public var onlineJoinRoomCode = ""
    @Published public var isOnlineRoomLoading = false
    /// Online display name, kept entirely separate from the local bot roster.
    /// Signing in overwrites this — never `seats`.
    @Published public var onlineDisplayName: String = ""
    /// The online table's own seat composition (you + invite/bot seats),
    /// independent of the local `seats` roster.
    @Published public var onlineComposition: [OnlineSeatSlot] = OnlineSeatSlot.defaultComposition(count: 3)
    @Published public var onlineVariant: PreferansVariant = .odesa {
        didSet {
            UserDefaults.standard.set(onlineVariant.rawValue, forKey: SettingsKeys.onlineVariant)
        }
    }
    @Published public var pulkaLimit: PulkaLimit = .standard {
        didSet {
            UserDefaults.standard.set(pulkaLimit.rawValue, forKey: SettingsKeys.pulkaLimit)
        }
    }

    public init() {
        let account = Self.loadRegisteredOnlineAccount()
        registeredOnlineAccount = account
        onlineDisplayName = account?.displayName
            ?? UserDefaults.standard.string(forKey: SettingsKeys.onlineDisplayName)
            ?? ""
        onlineVariant = Self.loadOnlineVariant()
        pulkaLimit = Self.loadPulkaLimit()
    }

    public func setSeatCount(_ count: Int) {
        seats = LobbySeat.resize(seats, to: count)
    }

    public var botCount: Int {
        seats.filter { $0.kind == .bot }.count
    }

    public var canAddBot: Bool {
        seats.count < 4
    }

    public var canRemoveBot: Bool {
        seats.count > 3 && seats.contains { $0.kind == .bot }
    }

    public func addBot() {
        guard canAddBot else { return }
        seats = LobbySeat.addBot(to: seats)
    }

    public func removeBot() {
        guard canRemoveBot,
              let index = seats.lastIndex(where: { $0.kind == .bot }) else {
            return
        }
        seats.remove(at: index)
    }

    public func setSeatName(_ name: String, at index: Int) {
        guard seats.indices.contains(index) else { return }
        seats[index].name = name
    }

    public func quickPlayVsBots() {
        seats = LobbySeat.quickPlayVsBots()
        startLocalTable()
    }

    public func watchBots() {
        seats = LobbySeat.demoBots(count: 3)
        startLocalTable(speedOverride: .instant)
    }

    public func startCloudflareOnlineRoom() {
        guard !isOnlineRoomLoading else { return }
        if let validation = onlineSetupValidationError {
            errorText = validation
            infoText = nil
            return
        }
        isOnlineRoomLoading = true
        errorText = nil
        infoText = nil
        let setup = onlineRoomSetup()
        let delay = onlineBotMoveDelay
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let session = try await CloudflareOnlineGameSession.createRoom(
                    peers: setup.peers,
                    localPlayerID: setup.localPlayer,
                    rules: setup.rules,
                    match: setup.match,
                    variantTag: onlineVariant.rawValue,
                    botMoveDelay: delay
                )
                await session.start()
                cloudOnlineSession = session
                onlineJoinRoomCode = session.roomCode
            } catch {
                errorText = error.localizedDescription
            }
            isOnlineRoomLoading = false
        }
    }

    public func joinCloudflareOnlineRoom() {
        guard !isOnlineRoomLoading,
              let roomCode = pendingJoinRoomCode else {
            return
        }
        if let validation = onlineIdentityValidationError {
            errorText = validation
            infoText = nil
            return
        }
        isOnlineRoomLoading = true
        errorText = nil
        infoText = nil
        let setup = onlineRoomSetup()
        guard let localPeer = setup.peers.first(where: { $0.playerID == setup.localPlayer }) else {
            errorText = String(localized: "Selected seat is not available.")
            isOnlineRoomLoading = false
            return
        }
        let delay = onlineBotMoveDelay
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let session = try await CloudflareOnlineGameSession.joinRoom(
                    roomCode: roomCode,
                    localPeer: localPeer,
                    rules: setup.rules,
                    match: setup.match,
                    variantTag: onlineVariant.rawValue,
                    botMoveDelay: delay
                )
                await session.start()
                cloudOnlineSession = session
                onlineJoinRoomCode = session.roomCode
            } catch {
                errorText = error.localizedDescription
            }
            isOnlineRoomLoading = false
        }
    }

    /// DEBUG/test affordance: an all-bot online room backed by the in-memory
    /// transport. Lands on the same waiting room as a real room — host taps
    /// Start and the bot seats play out — without a worker or a second device.
    public func startInMemoryOnlineRoom() {
        do {
            if let validation = onlineSetupValidationError {
                errorText = validation
                infoText = nil
                return
            }
            let players = OnlineSeatSlot.canonicalPlayerIDs(count: 3)
            let localPlayer = players[0]
            let account = normalizedOnlineAccount(for: localPlayer)
            let peers = players.enumerated().map { index, player -> OnlinePeer in
                index == 0
                    ? OnlinePeer(playerID: player, accountID: account.id, provider: account.provider, displayName: resolvedOnlineDisplayName)
                    : OnlinePeer(playerID: player, accountID: "\(OnlinePeer.botAccountPrefix)\(player.rawValue)", provider: .dev, displayName: String(localized: "Bot \(index + 1)"))
            }
            let automatedPlayers = Set(peers.map(\.playerID).filter { $0 != localPlayer })
            let session = try InMemoryOnlineGameSession(
                roomCode: makeRoomCode(),
                peers: peers,
                localPlayerID: localPlayer,
                hostPlayerID: peers.first?.playerID,
                automatedPlayerIDs: automatedPlayers,
                dealSource: RandomDealSource(),
                botDelay: onlineBotMoveDelay
            )
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await session.start(rules: self.onlineVariant.rules, match: self.selectedMatchSettings)
                    onlineSession = session
                    errorText = nil
                } catch {
                    session.stop()
                    errorText = error.localizedDescription
                }
            }
        } catch {
            errorText = error.localizedDescription
        }
    }

    public func leaveOnlineRoom() {
        onlineSession?.stop()
        onlineSession = nil
        cloudOnlineSession?.stop()
        cloudOnlineSession = nil
    }

    public func handleInviteURL(_ url: URL) {
        guard let roomCode = PreferansInviteLink.roomCode(from: url) else { return }
        onlineJoinRoomCode = roomCode
        errorText = nil
        infoText = String(localized: "Invite \(roomCode) is ready — tap Join to take a seat.")
    }

    public var pendingJoinRoomCode: String? {
        PreferansInviteLink.roomCode(from: onlineJoinRoomCode)
    }

    public func completeAppleRegistration(userID: String, fullName: PersonNameComponents?) {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .medium
        let formattedName = fullName.map { formatter.string(from: $0) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = formattedName?.isEmpty == false ? formattedName! : resolvedOnlineDisplayName
        guard !displayName.isEmpty else {
            errorText = String(localized: "Enter your name to play online.")
            return
        }
        let account = RegisteredOnlineAccount(
            provider: .apple,
            accountID: "apple:\(userID)",
            displayName: displayName
        )
        registeredOnlineAccount = account
        // Identity flows into the online display name only — never the local
        // bot roster (`seats`), which the online flow no longer touches.
        onlineDisplayName = displayName
        Self.saveRegisteredOnlineAccount(account)
        errorText = nil
    }

    public func clearRegisteredOnlineAccount() {
        registeredOnlineAccount = nil
        UserDefaults.standard.removeObject(forKey: SettingsKeys.onlineRegisteredAccount)
    }

    public func setOnlineDisplayName(_ name: String) {
        onlineDisplayName = name
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: SettingsKeys.onlineDisplayName)
        } else {
            UserDefaults.standard.set(trimmed, forKey: SettingsKeys.onlineDisplayName)
        }
    }

    public func setOnlineTableSize(_ count: Int) {
        onlineComposition = OnlineSeatSlot.resize(onlineComposition, to: count)
    }

    public func setOnlineSeatKind(_ kind: OnlineSeatSlot.Kind, at index: Int) {
        guard onlineComposition.indices.contains(index), index != 0 else { return }
        onlineComposition[index].kind = kind
    }

    /// Validity of the online setup. The seat composition is always structurally
    /// valid (slot 0 is always "you"); the only user-fixable error is a missing
    /// display name when not signed in.
    public var onlineSetupValidationError: String? {
        onlineIdentityValidationError
    }

    public var onlineIdentityValidationError: String? {
        currentOnlineDisplayName.isEmpty ? String(localized: "Enter your name to play online.") : nil
    }

    public var currentOnlineDisplayName: String {
        if let registeredName = registeredOnlineAccount?.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
           !registeredName.isEmpty {
            return registeredName
        }
        return onlineDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The account the worker indexes this device's games under: the registered
    /// Apple identity when signed in, otherwise the persisted anonymous ID (which
    /// only exists once the player has created/joined a room). Nil on a fresh
    /// install that never played online — the "Your games" list stays empty.
    public var currentOnlineAccountID: String? {
        if let registeredOnlineAccount {
            return registeredOnlineAccount.accountID
        }
        return UserDefaults.standard.string(forKey: SettingsKeys.onlineAnonymousAccountID)
    }

    /// Resume an in-progress online game from the "Your games" list. Rebuilds the
    /// local peer from the seat the summary records and this device's account, so
    /// the worker rebinds the original seat by `accountID`.
    public func resumeCloudflareOnlineRoom(_ summary: OnlineGameSummary) {
        guard !isOnlineRoomLoading else { return }
        guard let localPeer = resumeLocalPeer(for: summary) else {
            errorText = String(localized: "Sign in or set your name to resume your games.")
            infoText = nil
            return
        }
        isOnlineRoomLoading = true
        errorText = nil
        infoText = nil
        let delay = onlineBotMoveDelay
        let variantTag = summary.variant ?? onlineVariant.rawValue
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let session = try await CloudflareOnlineGameSession.resumeRoom(
                    roomCode: summary.roomCode,
                    localPeer: localPeer,
                    variantTag: variantTag,
                    botMoveDelay: delay
                )
                await session.start()
                cloudOnlineSession = session
                onlineJoinRoomCode = session.roomCode
            } catch {
                errorText = error.localizedDescription
            }
            isOnlineRoomLoading = false
        }
    }

    /// Give up an unfinished online game from the list (best-effort). The worker
    /// authorizes by the seat the account holds, so no host secret is needed.
    public func abandonOnlineGame(_ summary: OnlineGameSummary) async {
        do {
            try await CloudflareRoomTransport.abandon(
                roomCode: summary.roomCode,
                playerID: summary.youSeat
            )
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func resumeLocalPeer(for summary: OnlineGameSummary) -> OnlinePeer? {
        guard let accountID = currentOnlineAccountID else { return nil }
        let provider = registeredOnlineAccount?.provider ?? .dev
        let displayName = currentOnlineDisplayName.isEmpty
            ? String(localized: "You")
            : currentOnlineDisplayName
        return OnlinePeer(
            playerID: summary.youSeat,
            accountID: accountID,
            provider: provider,
            displayName: displayName
        )
    }

    private var onlineBotMoveDelay: Duration {
        TestHarness.fastBotDelay(in: ProcessInfo.processInfo.arguments)
            ? BotPacing.testFast
            : botSpeed.delay
    }

    /// The display name to advertise for the local seat online. Callers validate
    /// `onlineIdentityValidationError` before constructing a room, so an online
    /// seat is never intentionally advertised without a human-visible name.
    private var resolvedOnlineDisplayName: String {
        currentOnlineDisplayName
    }

    /// `speedOverride` lets the watch-bots demo run instantly without
    /// stomping the lobby's `botSpeed` picker; otherwise `.instant` would
    /// leak into the next "Sit down" flow and zero normal bot pacing.
    public func startLocalTable(speedOverride: BotMoveSpeed? = nil) {
        guard seats.validationError == nil else { return }
        do {
            let lobbyPlayers = seats.map { PlayerID($0.trimmedName) }
            // First dealer = last seat so the first seat is forehand on deal 1.
            let defaultDealer = lobbyPlayers.last
            let args = ProcessInfo.processInfo.arguments
            let configuration = TestHarness.resolveConfiguration(
                from: args,
                defaults: TestHarness.Defaults(
                    players: lobbyPlayers,
                    firstDealer: defaultDealer,
                    match: selectedMatchSettings
                )
            )

            let viewerPolicy = configuration.viewerPolicyOverride
                ?? defaultViewerPolicy(for: configuration.players)

            let model = try GameViewModel(
                players: configuration.players,
                rules: configuration.rules,
                match: configuration.match,
                firstDealer: configuration.firstDealer,
                viewerPolicy: viewerPolicy,
                dealSource: configuration.dealSource
            )

            if configuration.players.elementsEqual(lobbyPlayers) {
                let strategy = HeuristicStrategy()
                for (index, seat) in configuration.players.enumerated()
                    where seats.indices.contains(index) && seats[index].kind == .bot {
                    model.botStrategies[seat] = strategy
                }
            }

            if TestHarness.fastBotDelay(in: args) {
                model.botMoveDelay = BotPacing.testFast
            } else {
                model.botMoveDelay = (speedOverride ?? botSpeed).delay
            }

            let hasHumanSeat = seats.contains { $0.kind == .human }
            if TestHarness.skipTapToAdvance(in: args) || !hasHumanSeat {
                model.tapToAdvanceEnabled = false
            }

            localModel = model
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Builds the online peer set from the online seat composition + identity —
    /// deliberately independent of the local `seats` roster, so local bot names
    /// never leak into an online room. Player IDs come from a canonical pool
    /// (north/east/south/west) unless a UI test pins them via `-uiTestPlayers`;
    /// either way the player sees `displayName`, not the raw seat ID.
    private func onlineRoomSetup() -> (
        peers: [OnlinePeer],
        localPlayer: PlayerID,
        rules: PreferansRules,
        match: MatchSettings,
        dealSource: DealSource
    ) {
        let poolPlayers = OnlineSeatSlot.canonicalPlayerIDs(count: onlineComposition.count)
        let args = ProcessInfo.processInfo.arguments
        let configuration = TestHarness.resolveConfiguration(
            from: args,
            defaults: TestHarness.Defaults(
                players: poolPlayers,
                firstDealer: poolPlayers.last,
                match: selectedMatchSettings
            )
        )
        let players = configuration.players
        // The host always sits in the "you" slot (slot 0). A joiner declares the
        // same slot — the worker rebinds them to an open seat by accountID.
        let selectedIndex = min(onlineComposition.firstIndex { $0.kind == .you } ?? 0, max(0, players.count - 1))
        let localPlayer = players[selectedIndex]
        let account = normalizedOnlineAccount(for: localPlayer)
        let displayName = resolvedOnlineDisplayName
        let peers = players.enumerated().map { index, player -> OnlinePeer in
            let kind = onlineComposition.indices.contains(index) ? onlineComposition[index].kind : .invite
            if index == selectedIndex {
                return OnlinePeer(playerID: player, accountID: account.id, provider: account.provider, displayName: displayName)
            } else if kind == .bot {
                return OnlinePeer(
                    playerID: player,
                    accountID: "\(OnlinePeer.botAccountPrefix)\(player.rawValue)",
                    provider: .dev,
                    displayName: String(localized: "Bot \(index + 1)")
                )
            } else {
                return OnlinePeer(
                    playerID: player,
                    accountID: "\(OnlinePeer.pendingAccountPrefix)\(player.rawValue)",
                    provider: .dev,
                    displayName: String(localized: "Open seat")
                )
            }
        }
        let rules = args.contains(UITestFlags.matchScript)
            ? configuration.rules
            : onlineVariant.rules
        return (peers, localPlayer, rules, configuration.match, configuration.dealSource)
    }

    private func normalizedOnlineAccount(for player: PlayerID) -> (provider: OnlineAccountProvider, id: String) {
        if let registeredOnlineAccount {
            return (registeredOnlineAccount.provider, registeredOnlineAccount.accountID)
        }

        return (.dev, anonymousAccountID(for: player))
    }

    private func anonymousAccountID(for player: PlayerID) -> String {
        if let stored = UserDefaults.standard.string(forKey: SettingsKeys.onlineAnonymousAccountID),
           !stored.isEmpty {
            return stored
        }
        @Dependency(\.uuid) var uuid
        let accountID = "anonymous:\(player.rawValue.lowercased()):\(uuid().uuidString.lowercased())"
        UserDefaults.standard.set(accountID, forKey: SettingsKeys.onlineAnonymousAccountID)
        return accountID
    }

    private static func loadRegisteredOnlineAccount() -> RegisteredOnlineAccount? {
        guard let data = UserDefaults.standard.data(forKey: SettingsKeys.onlineRegisteredAccount) else {
            return nil
        }
        return try? PreferansJSONCoder.decoder.decode(RegisteredOnlineAccount.self, from: data)
    }

    private static func saveRegisteredOnlineAccount(_ account: RegisteredOnlineAccount) {
        guard let data = try? PreferansJSONCoder.encoder.encode(account) else { return }
        UserDefaults.standard.set(data, forKey: SettingsKeys.onlineRegisteredAccount)
    }

    private static func loadOnlineVariant() -> PreferansVariant {
        guard let raw = UserDefaults.standard.string(forKey: SettingsKeys.onlineVariant),
              let variant = PreferansVariant(rawValue: raw) else {
            return .odesa
        }
        return variant
    }

    private static func loadPulkaLimit() -> PulkaLimit {
        guard let raw = UserDefaults.standard.string(forKey: SettingsKeys.pulkaLimit),
              let limit = PulkaLimit(rawValue: raw) else {
            return .standard
        }
        return limit
    }

    private var selectedMatchSettings: MatchSettings {
        MatchSettings(poolTarget: pulkaLimit.target)
    }

    private func makeRoomCode() -> String {
        @Dependency(\.uuid) var uuid
        return String(uuid().uuidString.prefix(6))
    }

    /// Default viewer policy when a UI test hasn't forced an override.
    /// Always pinned to the first seat; there is no pass-the-device mode.
    private func defaultViewerPolicy(for players: [PlayerID]) -> ViewerPolicy {
        .pinned(players.first ?? PlayerID("player"))
    }
}

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
            return PreferansRules(
                requireWhistOnTenTrickContracts: true,
                singleWhistScoring: .ownHandOnly,
                failedDeclarerConsolation: .none,
                allPassPenaltyPolicy: .perTrick(multiplier: 2, amnesty: false),
                zeroTricksAllPassPoolBonus: 0
            )
        }
    }
}

public enum PulkaLimit: String, CaseIterable, Identifiable, Equatable, Codable {
    case short = "11"
    case standard = "21"

    public var id: String { rawValue }

    public var target: Int {
        switch self {
        case .short: return 11
        case .standard: return 21
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .short: return "11"
        case .standard: return "21"
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

public struct RegisteredOnlineAccount: Codable, Equatable {
    public var provider: OnlineAccountProvider
    public var accountID: String
    public var displayName: String

    public init(provider: OnlineAccountProvider, accountID: String, displayName: String) {
        self.provider = provider
        self.accountID = accountID
        self.displayName = displayName
    }
}

/// Single seat in the lobby's local-table roster. Folds the seat's
/// human/bot kind into the same struct as its name so the two can never drift.
public struct LobbySeat: Identifiable, Equatable {
    public enum Kind: Equatable { case human, bot }

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
                kind: index == 0 ? .human : .bot
            )
        }
    }

    static func quickPlayVsBots() -> [LobbySeat] {
        defaults(count: 3)
    }

    static func demoBots(count: Int) -> [LobbySeat] {
        defaults(count: count).map { seat in
            LobbySeat(id: seat.id, name: seat.name, kind: .bot)
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
        resized.append(LobbySeat(name: nextBotName(existing: existing), kind: .bot))
        return resized
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
        let bots = filter { $0.kind == .bot }.count
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
