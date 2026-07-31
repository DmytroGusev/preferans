import Dependencies
import SwiftUI
import PreferansEngine

@MainActor
public final class LobbyViewModel: ObservableObject {
    @Dependency(\.continuousClock) private var clock

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
    @Published public private(set) var onlineAccountSessionToken: String?
    @Published public var onlineJoinRoomCode = ""
    @Published public var isOnlineRoomLoading = false
    /// Online display name, kept entirely separate from the local bot roster.
    /// Signing in overwrites this — never `seats`.
    @Published public var onlineDisplayName: String = ""
    /// The online table's own seat composition (you + invite/bot seats),
    /// independent of the local `seats` roster.
    @Published public var onlineComposition: [OnlineSeatSlot] = OnlineSeatSlot.defaultComposition(count: 3)
    /// Shared convention for bot and online tables. The persisted key keeps its
    /// historical name, but the choice now seeds both rules and match closure.
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
    @Published public var customPulkaPerPlayer: Int = PulkaLimit.defaultCustomTarget {
        didSet {
            let clamped = Self.clampedPulkaPerPlayer(customPulkaPerPlayer)
            if customPulkaPerPlayer != clamped {
                customPulkaPerPlayer = clamped
                return
            }
            UserDefaults.standard.set(customPulkaPerPlayer, forKey: SettingsKeys.customPulkaPerPlayer)
        }
    }
    @Published public var customPulkaTableTotal: Int = PulkaLimit.defaultCustomTableTarget {
        didSet {
            let clamped = Self.clampedPulkaTableTotal(customPulkaTableTotal)
            if customPulkaTableTotal != clamped {
                customPulkaTableTotal = clamped
                return
            }
            UserDefaults.standard.set(customPulkaTableTotal, forKey: SettingsKeys.customPulkaTableTotal)
        }
    }
    private var onlineNamePersistenceTask: Task<Void, Never>?
    private let accountClient: CloudflareAccountClient
    static let onlineNamePersistenceDelay: Duration = .milliseconds(300)

    public init(accountClient: CloudflareAccountClient = CloudflareAccountClient()) {
        self.accountClient = accountClient
        let account = Self.loadRegisteredOnlineAccount()
        let sessionToken = account == nil ? nil : OnlineAccountSessionStore.token()
        registeredOnlineAccount = sessionToken == nil ? nil : account
        onlineAccountSessionToken = sessionToken
        onlineDisplayName = account?.displayName
            ?? UserDefaults.standard.string(forKey: SettingsKeys.onlineDisplayName)
            ?? ""
        onlineVariant = Self.loadOnlineVariant()
        pulkaLimit = Self.loadPulkaLimit()
        customPulkaPerPlayer = Self.loadCustomPulkaPerPlayer()
        customPulkaTableTotal = Self.loadCustomPulkaTableTotal()
    }

    deinit {
        onlineNamePersistenceTask?.cancel()
    }

    public func setSeatCount(_ count: Int) {
        seats = LobbySeat.resize(seats, to: count)
    }

    public var botCount: Int {
        seats.filter(\.isBot).count
    }

    public var canAddBot: Bool {
        seats.count < 4
    }

    public var canRemoveBot: Bool {
        seats.count > 3 && seats.contains(where: \.isBot)
    }

    public func addBot() {
        guard canAddBot else { return }
        seats = LobbySeat.addBot(to: seats)
    }

    public func removeBot() {
        guard canRemoveBot,
              let index = seats.lastIndex(where: \.isBot) else {
            return
        }
        seats.remove(at: index)
    }

    public func setSeatName(_ name: String, at index: Int) {
        guard seats.indices.contains(index) else { return }
        seats[index].name = name
    }

    public func setBotProfile(_ profile: BotProfile, at index: Int) {
        guard seats.indices.contains(index) else { return }
        seats[index].setBotProfile(profile)
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
            rejectOnlineOperation(validation)
            return
        }
        let setup = onlineRoomSetup()
        guard let accountSessionToken = onlineAccountSessionToken else { return }
        let delay = onlineBotMoveDelay
        let variantTag = onlineVariant.rawValue
        launchCloudRoom {
            try await CloudflareOnlineGameSession.createRoom(
                peers: setup.peers,
                localPlayerID: setup.localPlayer,
                accountSessionToken: accountSessionToken,
                rules: setup.rules,
                match: setup.match,
                variantTag: variantTag,
                botMoveDelay: delay
            )
        }
    }

    public func joinCloudflareOnlineRoom() {
        guard !isOnlineRoomLoading,
              let roomCode = pendingJoinRoomCode else {
            return
        }
        if let validation = onlineIdentityValidationError {
            rejectOnlineOperation(validation)
            return
        }
        let setup = onlineRoomSetup()
        guard let accountSessionToken = onlineAccountSessionToken else { return }
        guard let localPeer = setup.peers.first(where: { $0.playerID == setup.localPlayer }) else {
            rejectOnlineOperation(String(localized: "Selected seat is not available."))
            return
        }
        let delay = onlineBotMoveDelay
        let variantTag = onlineVariant.rawValue
        launchCloudRoom {
            try await CloudflareOnlineGameSession.joinRoom(
                roomCode: roomCode,
                localPeer: localPeer,
                accountSessionToken: accountSessionToken,
                rules: setup.rules,
                match: setup.match,
                variantTag: variantTag,
                botMoveDelay: delay
            )
        }
    }

    /// DEBUG/test affordance: an all-bot online room backed by the in-memory
    /// transport. Lands on the same waiting room as a real room — host taps
    /// Start and the bot seats play out — without a worker or a second device.
    public func startInMemoryOnlineRoom() {
        do {
            if currentOnlineDisplayName.isEmpty {
                rejectOnlineOperation(String(localized: "Enter your name to play online."))
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
                    try await session.start(
                        rules: self.onlineVariant.rules,
                        match: self.selectedMatchSettings(playerCount: players.count)
                    )
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

    public func registerGuestOnlineAccount() {
        let displayName = onlineDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else {
            rejectOnlineOperation(String(localized: "Enter your name to play online."))
            return
        }
        registerOnlineAccount {
            try await self.accountClient.registerGuest(displayName: displayName)
        }
    }

    public func completeAppleRegistration(
        identityToken: String,
        nonce: String,
        fullName: PersonNameComponents?
    ) {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .medium
        let formattedName = fullName.map { formatter.string(from: $0) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = formattedName?.isEmpty == false ? formattedName! : resolvedOnlineDisplayName
        guard !displayName.isEmpty else {
            errorText = String(localized: "Enter your name to play online.")
            return
        }
        registerOnlineAccount {
            try await self.accountClient.registerApple(
                identityToken: identityToken,
                nonce: nonce,
                displayName: displayName
            )
        }
    }

    public func clearRegisteredOnlineAccount() {
        registeredOnlineAccount = nil
        onlineAccountSessionToken = nil
        OnlineAccountSessionStore.remove()
        OnlineSeatCredentialStore.removeAll()
        UserDefaults.standard.removeObject(forKey: SettingsKeys.onlineRegisteredAccount)
    }

    public func setOnlineDisplayName(_ name: String) {
        onlineDisplayName = name
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        onlineNamePersistenceTask?.cancel()
        let clock = self.clock
        onlineNamePersistenceTask = Task { @MainActor [weak self] in
            do {
                try await clock.sleep(for: Self.onlineNamePersistenceDelay)
            } catch {
                return
            }
            guard let self,
                  onlineDisplayName.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else {
                return
            }
            Self.persistOnlineDisplayName(trimmed)
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
        if currentOnlineDisplayName.isEmpty {
            return String(localized: "Enter your name to play online.")
        }
        if registeredOnlineAccount == nil || onlineAccountSessionToken == nil {
            return String(localized: "Register as a guest or sign in with Apple to play online.")
        }
        return nil
    }

    public var currentOnlineDisplayName: String {
        if let registeredName = registeredOnlineAccount?.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
           !registeredName.isEmpty {
            return registeredName
        }
        return onlineDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The server-issued v2 account this device's game library belongs to.
    /// Nil until the player explicitly registers as a guest or with Apple.
    public var currentOnlineAccountID: String? {
        registeredOnlineAccount?.accountID
    }

    /// Resume an in-progress online game from the "Your games" list. Rebuilds the
    /// local peer from the seat the summary records and this device's account, so
    /// the worker rebinds the original seat by `accountID`.
    public func resumeCloudflareOnlineRoom(_ summary: OnlineGameSummary) {
        guard !isOnlineRoomLoading else { return }
        guard let localPeer = resumeLocalPeer(for: summary) else {
            rejectOnlineOperation(String(localized: "Sign in or set your name to resume your games."))
            return
        }
        guard let accountSessionToken = onlineAccountSessionToken else {
            rejectOnlineOperation(String(localized: "Register again to resume your games."))
            return
        }
        let delay = onlineBotMoveDelay
        let variantTag = summary.variant ?? onlineVariant.rawValue
        launchCloudRoom {
            try await CloudflareOnlineGameSession.resumeRoom(
                roomCode: summary.roomCode,
                localPeer: localPeer,
                accountSessionToken: accountSessionToken,
                variantTag: variantTag,
                botMoveDelay: delay
            )
        }
    }

    /// Owns the shared create/join/resume lifecycle: one busy gate, one place
    /// that clears stale messages, starts the returned session, publishes it,
    /// and restores the idle state on both success and failure.
    private func launchCloudRoom(
        operation: @escaping @MainActor () async throws -> CloudflareOnlineGameSession
    ) {
        guard !isOnlineRoomLoading else { return }
        isOnlineRoomLoading = true
        errorText = nil
        infoText = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isOnlineRoomLoading = false }
            do {
                let session = try await operation()
                await session.start()
                cloudOnlineSession = session
                onlineJoinRoomCode = session.roomCode
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func registerOnlineAccount(
        operation: @escaping @MainActor () async throws -> OnlineAccountRegistration
    ) {
        guard !isOnlineRoomLoading else { return }
        isOnlineRoomLoading = true
        errorText = nil
        infoText = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isOnlineRoomLoading = false }
            do {
                let registration = try await operation()
                guard OnlineAccountSessionStore.store(registration.sessionToken) else {
                    throw CloudflareRoomTransportError.serverError("Could not securely save the online session.")
                }
                registeredOnlineAccount = registration.account
                onlineAccountSessionToken = registration.sessionToken
                onlineDisplayName = registration.account.displayName
                Self.saveRegisteredOnlineAccount(registration.account)
                UserDefaults.standard.removeObject(forKey: SettingsKeys.onlineAnonymousAccountID)
                errorText = nil
                infoText = String(localized: "Online account ready.")
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func rejectOnlineOperation(_ message: String) {
        errorText = message
        infoText = nil
    }

    /// Give up an unfinished online game from the list (best-effort). The worker
    /// authorizes by the seat the account holds — proven by the stored seat
    /// token plus the authenticated account session.
    public func abandonOnlineGame(_ summary: OnlineGameSummary) async {
        do {
            guard let seatToken = OnlineSeatCredentialStore.token(for: summary.roomCode),
                  let accountSessionToken = onlineAccountSessionToken else {
                throw CloudflareRoomTransportError.serverError("Register again to manage this game.")
            }
            try await CloudflareRoomTransport.abandon(
                roomCode: summary.roomCode,
                playerID: summary.youSeat,
                seatToken: seatToken,
                accountSessionToken: accountSessionToken
            )
            OnlineSeatCredentialStore.remove(roomCode: summary.roomCode)
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
                    rules: onlineVariant.rules,
                    match: selectedMatchSettings(playerCount: lobbyPlayers.count)
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
                for (index, seat) in configuration.players.enumerated()
                    where seats.indices.contains(index) && seats[index].isBot {
                    guard let profile = seats[index].botProfile else { continue }
                    model.botStrategies[seat] = HeuristicStrategy(profile: profile)
                }
            }

            if TestHarness.fastBotDelay(in: args) {
                model.botMoveDelay = BotPacing.testFast
            } else {
                model.botMoveDelay = (speedOverride ?? botSpeed).delay
            }

            let hasHumanSeat = seats.contains { !$0.isBot }
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
                rules: onlineVariant.rules,
                match: selectedMatchSettings(playerCount: poolPlayers.count)
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
        return (peers, localPlayer, configuration.rules, configuration.match, configuration.dealSource)
    }

    private func normalizedOnlineAccount(for player: PlayerID) -> (provider: OnlineAccountProvider, id: String) {
        if let registeredOnlineAccount {
            return (registeredOnlineAccount.provider, registeredOnlineAccount.accountID)
        }
        // Used only by the explicitly in-memory DEBUG/test room. Real worker
        // paths are gated on a v2 server registration before this is reached.
        return (.dev, "in-memory:\(player.rawValue.lowercased())")
    }

    private static func loadRegisteredOnlineAccount() -> RegisteredOnlineAccount? {
        guard let data = UserDefaults.standard.data(forKey: SettingsKeys.onlineRegisteredAccount) else {
            return nil
        }
        guard let account = try? PreferansJSONCoder.decoder.decode(RegisteredOnlineAccount.self, from: data),
              account.schemaVersion == AppIdentifiers.cloudSchemaVersion,
              account.provider == .apple || account.provider == .guest else {
            UserDefaults.standard.removeObject(forKey: SettingsKeys.onlineRegisteredAccount)
            UserDefaults.standard.removeObject(forKey: SettingsKeys.onlineAnonymousAccountID)
            return nil
        }
        return account
    }

    private static func persistOnlineDisplayName(_ name: String) {
        if name.isEmpty {
            UserDefaults.standard.removeObject(forKey: SettingsKeys.onlineDisplayName)
        } else {
            UserDefaults.standard.set(name, forKey: SettingsKeys.onlineDisplayName)
        }
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

    private static func loadCustomPulkaPerPlayer() -> Int {
        guard let stored = UserDefaults.standard.object(forKey: SettingsKeys.customPulkaPerPlayer) as? Int else {
            return PulkaLimit.defaultCustomTarget
        }
        return clampedPulkaPerPlayer(stored)
    }

    private static func clampedPulkaPerPlayer(_ value: Int) -> Int {
        min(max(value, PulkaLimit.customRange.lowerBound), PulkaLimit.customRange.upperBound)
    }

    private static func loadCustomPulkaTableTotal() -> Int {
        guard let stored = UserDefaults.standard.object(forKey: SettingsKeys.customPulkaTableTotal) as? Int else {
            return PulkaLimit.defaultCustomTableTarget
        }
        return clampedPulkaTableTotal(stored)
    }

    private static func clampedPulkaTableTotal(_ value: Int) -> Int {
        min(max(value, PulkaLimit.customTableRange.lowerBound), PulkaLimit.customTableRange.upperBound)
    }

    public var pulkaPerPlayer: Int {
        pulkaLimit.target(custom: customPulkaPerPlayer)
    }

    public func totalPulkaTarget(playerCount: Int) -> Int {
        if onlineVariant.poolClosure == .tableTotal, pulkaLimit == .custom {
            return customPulkaTableTotal
        }
        return pulkaPerPlayer * max(1, playerCount)
    }

    private func selectedMatchSettings(playerCount: Int) -> MatchSettings {
        MatchSettings(
            poolTarget: totalPulkaTarget(playerCount: playerCount),
            poolClosure: onlineVariant.poolClosure,
            raspasy: onlineVariant.raspasy
        )
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
