import SwiftUI
import PreferansEngine
#if canImport(GameKit) && canImport(UIKit)
import GameKit
#endif

public struct LobbyView: View {
    #if canImport(GameKit) && canImport(UIKit)
    @EnvironmentObject private var gameCenter: GameCenterService
    @EnvironmentObject private var online: HostedOnlineGameCoordinator
    #endif

    @State private var localModel: GameViewModel?
    @State private var onlineSession: InMemoryOnlineGameSession?
    @State private var cloudOnlineSession: CloudflareOnlineGameSession?
    @State private var seats: [LobbySeat] = LobbySeat.defaults(count: 3)
    @State private var botSpeed: BotMoveSpeed = .normal
    @State private var errorText: String?
    @State private var onlineAccountEmail = "neo@example.test"
    @State private var onlineSeatIndex = 0
    @State private var onlineJoinRoomCode = ""
    @State private var isOnlineRoomLoading = false
    @State private var showingMatchmaker = false
    @State private var hasAttemptedSignIn = false
    @State private var showingSettings = false
    @State private var showingWatchBotsConfirm = false
    @State private var showingConventionLegend = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if let localModel {
                    LocalGameScreen(
                        model: localModel,
                        onLeaveTable: { self.localModel = nil },
                        onRematch: { startLocalTable() }
                    )
                } else if let onlineSession {
                    OnlineRoomGameScreen(
                        coordinator: onlineSession.localCoordinator,
                        roomCode: onlineSession.roomCode,
                        onLeaveTable: { leaveOnlineRoom() }
                    )
                } else if let cloudOnlineSession {
                    OnlineRoomGameScreen(
                        coordinator: cloudOnlineSession.localCoordinator,
                        roomCode: cloudOnlineSession.roomCode,
                        inviteURL: cloudOnlineSession.inviteURL,
                        onLeaveTable: { leaveOnlineRoom() }
                    )
                } else {
                    #if canImport(GameKit) && canImport(UIKit)
                    if let projection = online.projection {
                        ProjectionGameScreen(
                            projection: projection,
                            eventLog: online.eventLog,
                            recentEvents: online.recentEvents,
                            onSend: online.send,
                            onLeaveTable: { online.detach() },
                            extraMenu: { EmptyView() }
                        )
                    } else {
                        lobbyContent
                    }
                    #else
                    lobbyContent
                    #endif
                }
            }
            .toolbar {
                if localModel == nil && onlineSession == nil && cloudOnlineSession == nil {
                    ToolbarItem(placement: .automatic) {
                        Button { showingSettings = true } label: {
                            Image(systemName: "gearshape.fill")
                                .foregroundStyle(TableTheme.goldBright)
                                .accessibilityLabel("Settings")
                        }
                        .accessibilityIdentifier(UIIdentifiers.lobbySettingsButton)
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsScreen()
            }
            .sheet(isPresented: $showingConventionLegend) {
                ConventionLegendSheet()
            }
            .confirmationDialog(
                "Watch the bots play?",
                isPresented: $showingWatchBotsConfirm,
                titleVisibility: .visible
            ) {
                Button("Watch") { watchBots() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All three seats will be filled with bots and you'll spectate the match. Your roster will be replaced.")
            }
        }
        .onOpenURL { url in
            handleInviteURL(url)
        }
        #if canImport(GameKit) && canImport(UIKit)
        .background(GameCenterAuthenticationPresenter(viewController: gameCenter.authenticationViewController).frame(width: 0, height: 0))
        .sheet(isPresented: $showingMatchmaker) {
            GameCenterMatchmakerView(
                minPlayers: 3,
                maxPlayers: 4,
                onMatch: { match in
                    showingMatchmaker = false
                    Task { await online.attach(match: match) }
                },
                onCancel: { showingMatchmaker = false },
                onError: { error in
                    showingMatchmaker = false
                    errorText = error.localizedDescription
                }
            )
        }
        #endif
    }

    private var lobbyContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                localTableCard
                onlineRoomCard
                #if canImport(GameKit) && canImport(UIKit)
                gameCenterOnlineCard
                #endif
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier(UIIdentifiers.lobbyError)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 110)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            lobbyStartBar
        }
        .onChange(of: seats.count) { _, count in
            onlineSeatIndex = min(onlineSeatIndex, max(0, count - 1))
        }
        .feltBackground()
    }

    /// Hero on the felt: gold suit glyph, large cream title, gold subtitle
    /// rule. Replaces the system-grouped-background hero so the lobby
    /// reads as the same continuous environment as the table.
    private var hero: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(TableTheme.gold.opacity(0.16))
                    .frame(width: 78, height: 78)
                    .overlay(
                        Circle().strokeBorder(TableTheme.gold.opacity(0.45), lineWidth: 0.75)
                    )
                Image(systemName: "suit.spade.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(TableTheme.goldBright)
            }
            Text("Preferans")
                .font(.largeTitle.bold())
                .foregroundStyle(TableTheme.inkCream)
                .accessibilityIdentifier(UIIdentifiers.lobbyTitle)
            houseConventionTagline
        }
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    /// Hero tagline: four house-named conventions in their renamed forms
    /// (Одеса, Wien, Θεσσαλονίκη, Крути) instead of the standard
    /// Sochi / Leningrad / Rostov / Stalingrad. Each name carries its own
    /// `.help(...)` (hover tooltip on iPad-with-pointer / Mac Catalyst /
    /// macOS) and `.accessibilityHint(...)` (VoiceOver) mapping it back to
    /// the standard name plus a one-line description. Tapping anywhere on
    /// the row opens the full legend sheet — that's the iPhone fallback for
    /// devices without hover.
    private var houseConventionTagline: some View {
        Button {
            showingConventionLegend = true
        } label: {
            HStack(spacing: 6) {
                conventionPill(verbatim: "Одеса",
                               helpKey: "convention.odesa.help",
                               hintKey: "convention.odesa.hint")
                conventionDot
                conventionPill(verbatim: "Wien",
                               helpKey: "convention.wien.help",
                               hintKey: "convention.wien.hint")
                conventionDot
                conventionPill(verbatim: "Θεσσαλονίκη",
                               helpKey: "convention.thessaloniki.help",
                               hintKey: "convention.thessaloniki.hint")
                conventionDot
                conventionPill(verbatim: "Крути",
                               helpKey: "convention.kruty.help",
                               hintKey: "convention.kruty.hint")
            }
            .font(.footnote.weight(.semibold))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(TableTheme.gold)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
        }
        .buttonStyle(.plain)
        .help("convention.tagline.help")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("convention.tagline.accessibilityLabel")
        .accessibilityHint("convention.tagline.accessibilityHint")
        .accessibilityIdentifier(UIIdentifiers.lobbyHouseConventions)
    }

    private func conventionPill(verbatim name: String,
                                helpKey: LocalizedStringKey,
                                hintKey: LocalizedStringKey) -> some View {
        Text(verbatim: name)
            .help(helpKey)
            .accessibilityLabel(Text(verbatim: name))
            .accessibilityHint(hintKey)
    }

    private var conventionDot: some View {
        Text(verbatim: "·")
            .foregroundStyle(TableTheme.gold.opacity(0.45))
            .accessibilityHidden(true)
    }

    private var localTableCard: some View {
        card(title: "At this table", icon: "person.3.fill") {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    seatCountButton(count: 3, id: UIIdentifiers.lobbyPlayerCountThree)
                    seatCountButton(count: 4, id: UIIdentifiers.lobbyPlayerCountFour)
                }

                VStack(spacing: 8) {
                    ForEach(Array(seats.enumerated()), id: \.element.id) { index, _ in
                        seatRow(index: index)
                    }
                }

                botSpeedPicker

                if let validation = seats.validationError {
                    Text(validation)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier(UIIdentifiers.lobbyValidationError)
                }

                // Hidden test-only affordance. The visible quick-play CTA was
                // folded into "Sit down" (which already starts a table with
                // the current roster), but UI tests still tap this identifier
                // to land on a 1-human + 2-bot table from a clean lobby.
                Button { quickPlayVsBots() } label: { Color.clear }
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .allowsHitTesting(true)
                    .accessibilityIdentifier(UIIdentifiers.lobbyQuickPlayVsBots)

                // Spectator-only "watch bots" lives below the roster as a
                // secondary affordance — the main "Sit down" CTA in the
                // sticky bottom bar is the primary play path. The old
                // "Deal me in" button has been folded into Sit Down so the
                // lobby has one CTA instead of two competing ones.
                Button {
                    showingWatchBotsConfirm = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "eye.fill")
                            .foregroundStyle(TableTheme.goldBright)
                        Text("Watch bots play")
                            .fontWeight(.semibold)
                            .foregroundStyle(TableTheme.inkCream)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(TableTheme.inkCreamSoft)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(UIIdentifiers.lobbyWatchBots)
            }
        }
    }

    private var lobbyStartBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(TableTheme.gold.opacity(0.18))
                .frame(height: 0.5)
            Button {
                startLocalTable()
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Sit down")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.feltPrimary)
            .controlSize(.large)
            .disabled(seats.validationError != nil)
            .accessibilityIdentifier(UIIdentifiers.lobbyStartLocalTable)
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.32), Color.black.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func seatRow(index: Int) -> some View {
        let isBot = seats[index].kind == .bot
        let isViewer = index == 0 && !isBot
        return HStack(spacing: 10) {
            Image(systemName: isBot ? "cpu" : "person.crop.circle.fill")
                .foregroundStyle(isBot ? TableTheme.gold : TableTheme.goldBright)
                .font(.title3)
            TextField("Seat \(index + 1)", text: nameBinding(for: index))
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .foregroundStyle(TableTheme.inkCream)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(UIIdentifiers.lobbyPlayerNameField(index: index))
            if isViewer {
                Text("badge.you")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(TableTheme.feltDeep)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(TableTheme.goldBright, in: Capsule())
            } else {
                Text("badge.bot")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(TableTheme.inkCreamSoft)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.30), in: Capsule())
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
    }

    private var botSpeedPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bot speed")
                .font(.caption.weight(.semibold))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(TableTheme.gold)
            Picker("Bot speed", selection: $botSpeed) {
                ForEach(BotMoveSpeed.allCases) { speed in
                    Text(speed.label).tag(speed)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(UIIdentifiers.lobbyBotSpeedPicker)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var onlineRoomCard: some View {
        card(title: "Invite room", icon: "link") {
            VStack(spacing: 12) {
                TextField("email@example.test", text: $onlineAccountEmail)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .foregroundStyle(TableTheme.inkCream)
                    .padding(10)
                    .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier(UIIdentifiers.onlineAccountEmail)

                Picker("Seat", selection: $onlineSeatIndex) {
                    ForEach(Array(seats.enumerated()), id: \.element.id) { index, seat in
                        Text(seat.trimmedName.isEmpty ? "Seat \(index + 1)" : seat.trimmedName)
                            .tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier(UIIdentifiers.onlineLocalSeatPicker)

                Button {
                    startCloudflareOnlineRoom()
                } label: {
                    HStack {
                        if isOnlineRoomLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "person.3.sequence.fill")
                        }
                        Text("Create invite room")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.feltPrimary)
                .disabled(seats.validationError != nil || isOnlineRoomLoading)
                .accessibilityIdentifier(UIIdentifiers.onlineCreateRoom)

                HStack(spacing: 8) {
                    TextField("Room code", text: $onlineJoinRoomCode)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .foregroundStyle(TableTheme.inkCream)
                        .padding(10)
                        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier(UIIdentifiers.onlineJoinRoomCode)

                    Button {
                        joinCloudflareOnlineRoom()
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TableTheme.goldBright)
                    .disabled(isOnlineRoomLoading || PreferansInviteLink.normalizedRoomCode(onlineJoinRoomCode) == nil)
                    .accessibilityLabel("Join table")
                    .accessibilityIdentifier(UIIdentifiers.onlineJoinRoom)
                }

                #if DEBUG
                Button {
                    startInMemoryOnlineRoom()
                } label: {
                    HStack {
                        Image(systemName: "testtube.2")
                        Text("Run local test room")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.feltSecondary)
                .disabled(seats.validationError != nil || isOnlineRoomLoading)
                .accessibilityIdentifier(UIIdentifiers.onlineCreateTestRoom)
                #endif
            }
        }
    }

    #if canImport(GameKit) && canImport(UIKit)
    private var gameCenterOnlineCard: some View {
        card(title: "Game Center", icon: "globe") {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(gameCenter.isAuthenticated ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(onlineStatusLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Button {
                    if gameCenter.isAuthenticated {
                        showingMatchmaker = true
                    } else {
                        hasAttemptedSignIn = true
                        gameCenter.authenticate()
                    }
                } label: {
                    HStack {
                        Image(systemName: gameCenter.isAuthenticated ? "magnifyingglass" : "person.crop.circle.badge.questionmark")
                        Text(onlineButtonTitle)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                // Only surface online errors after the user has actively
                // tried to use the online table — pre-opt-in error states
                // ("local player not authenticated" before any tap) are
                // expected and not actionable yet.
                if hasAttemptedSignIn, let onlineError = online.errorText {
                    Text(onlineError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var onlineStatusLine: String {
        if gameCenter.isAuthenticated || hasAttemptedSignIn {
            return gameCenter.statusText
        }
        return String(localized: "Sign in to find a table")
    }

    private var onlineButtonTitle: LocalizedStringKey {
        gameCenter.isAuthenticated ? "Find a table" : "Sign in to Game Center"
    }
    #endif

    private func card<Content: View>(title: LocalizedStringKey, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(TableTheme.goldBright)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(TableTheme.inkCream)
            }
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(TableTheme.gold.opacity(0.22), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func seatCountButton(count: Int, id: String) -> some View {
        let isSelected = seats.count == count
        Button { setSeatCount(count) } label: {
            Text("\(count) players")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(FeltButtonStyle(emphasis: isSelected ? .primary : .secondary))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    private func nameBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { seats.indices.contains(index) ? seats[index].name : "" },
            set: { newValue in
                guard seats.indices.contains(index) else { return }
                seats[index].name = newValue
            }
        )
    }

    private func setSeatCount(_ count: Int) {
        seats = LobbySeat.resize(seats, to: count)
    }

    private func quickPlayVsBots() {
        seats = LobbySeat.quickPlayVsBots()
        startLocalTable()
    }

    private func watchBots() {
        seats = LobbySeat.demoBots(count: 3)
        startLocalTable(speedOverride: .instant)
    }

    private func startCloudflareOnlineRoom() {
        guard seats.validationError == nil, !isOnlineRoomLoading else { return }
        isOnlineRoomLoading = true
        errorText = nil
        let setup = onlineRoomSetup()
        Task { @MainActor in
            do {
                let session = try await CloudflareOnlineGameSession.createRoom(
                    peers: setup.peers,
                    localPlayerID: setup.localPlayer,
                    rules: setup.rules
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

    private func joinCloudflareOnlineRoom() {
        guard !isOnlineRoomLoading,
              let roomCode = PreferansInviteLink.normalizedRoomCode(onlineJoinRoomCode) else {
            return
        }
        isOnlineRoomLoading = true
        errorText = nil
        let setup = onlineRoomSetup()
        guard let localPeer = setup.peers.first(where: { $0.playerID == setup.localPlayer }) else {
            errorText = "Selected seat is not available."
            isOnlineRoomLoading = false
            return
        }
        Task { @MainActor in
            do {
                let session = try await CloudflareOnlineGameSession.joinRoom(
                    roomCode: roomCode,
                    localPeer: localPeer,
                    rules: setup.rules
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

    private func startInMemoryOnlineRoom() {
        guard seats.validationError == nil else { return }
        do {
            let setup = onlineRoomSetup()
            let automatedPlayers = Set(setup.peers.map(\.playerID).filter { $0 != setup.localPlayer })
            let session = try InMemoryOnlineGameSession(
                roomCode: makeRoomCode(),
                peers: setup.peers,
                localPlayerID: setup.localPlayer,
                hostPlayerID: setup.peers.first?.playerID,
                automatedPlayerIDs: automatedPlayers,
                dealSource: setup.dealSource,
                botDelay: TestHarness.fastBotDelay(in: ProcessInfo.processInfo.arguments) ? BotPacing.testFast : botSpeed.delay
            )
            Task { @MainActor in
                do {
                    try await session.start(rules: setup.rules)
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

    private func leaveOnlineRoom() {
        onlineSession?.stop()
        onlineSession = nil
        cloudOnlineSession?.stop()
        cloudOnlineSession = nil
    }

    private func handleInviteURL(_ url: URL) {
        guard let roomCode = PreferansInviteLink.roomCode(from: url) else { return }
        onlineJoinRoomCode = roomCode
        errorText = "Invite \(roomCode) is ready. Choose your seat and join the table."
    }

    private func onlineRoomSetup() -> (
        peers: [OnlinePeer],
        localPlayer: PlayerID,
        rules: PreferansRules,
        dealSource: DealSource
    ) {
        let lobbyPlayers = seats.map { PlayerID($0.trimmedName) }
        let defaultDealer = lobbyPlayers.last
        let args = ProcessInfo.processInfo.arguments
        let configuration = TestHarness.resolveConfiguration(
            from: args,
            defaults: TestHarness.Defaults(players: lobbyPlayers, firstDealer: defaultDealer)
        )
        let players = configuration.players
        let selectedIndex = min(onlineSeatIndex, max(0, players.count - 1))
        let localPlayer = players[selectedIndex]
        let account = normalizedOnlineAccount(for: localPlayer)
        let peers = players.enumerated().map { index, player in
            OnlinePeer(
                playerID: player,
                accountID: index == selectedIndex ? account.id : "pending:\(player.rawValue)",
                provider: index == selectedIndex ? account.provider : .dev,
                displayName: player.rawValue
            )
        }
        return (peers, localPlayer, configuration.rules, configuration.dealSource)
    }

    private func normalizedOnlineAccount(for player: PlayerID) -> (provider: OnlineAccountProvider, id: String) {
        let trimmed = onlineAccountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return (.dev, "dev:\(player.rawValue.lowercased())@example.test")
        }
        if trimmed.hasPrefix("dev:") {
            return (.dev, trimmed)
        }
        return (.email, "email:\(trimmed.lowercased())")
    }

    private func makeRoomCode() -> String {
        String(UUID().uuidString.prefix(6))
    }

    /// `speedOverride` lets the watch-bots demo run instantly without
    /// stomping the lobby's `botSpeed` picker — otherwise the .instant
    /// setting would leak into the next "Sit down" and silently zero
    /// the bot delay for normal play.
    private func startLocalTable(speedOverride: BotMoveSpeed? = nil) {
        guard seats.validationError == nil else { return }
        do {
            let lobbyPlayers = seats.map { PlayerID($0.trimmedName) }
            // First dealer = last seat so the first seat (the human) is
            // forehand (first to bid) on deal 1. In 4-player this also keeps
            // the human player active during the very first hand instead of
            // sitting out.
            let defaultDealer = lobbyPlayers.last
            let args = ProcessInfo.processInfo.arguments
            let configuration = TestHarness.resolveConfiguration(
                from: args,
                defaults: TestHarness.Defaults(players: lobbyPlayers, firstDealer: defaultDealer)
            )

            // Viewer policy: always pin. There is no hot-seat mode — every
            // production roster (1 human + bots, or all-bots watch demo) gets
            // a fixed perspective so the device never reveals a bot's hand by
            // rotating the viewer onto its seat. UI tests can still force
            // `.followsActor` via the launch flag.
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
            // Bot wiring is a property of the lobby's roster — when the
            // user explicitly toggled a seat to "bot", the engine should
            // play that seat autonomously. A script-driven UI test that
            // overrides the roster wholesale (different player IDs and
            // possibly a different seat count) is asking to drive every
            // seat itself; we don't impose the lobby's bot toggles on
            // a roster the user never actually saw.
            if configuration.players.elementsEqual(lobbyPlayers) {
                let strategy = HeuristicStrategy()
                for (index, seat) in configuration.players.enumerated()
                    where seats.indices.contains(index) && seats[index].kind == .bot {
                    model.botStrategies[seat] = strategy
                }
            }
            // Bot pacing follows the lobby's Bot speed picker. Automated
            // UI tests pass `-uiTestFastBotDelay` to short-circuit it
            // (`BotPacing.testFast`); manual `bin/sim` runs and shipping
            // builds never see that path. The animations flag deliberately
            // doesn't zero pacing — an interactive sim run with animations
            // off should still take turns at human speed.
            if TestHarness.fastBotDelay(in: args) {
                model.botMoveDelay = BotPacing.testFast
            } else {
                model.botMoveDelay = (speedOverride ?? botSpeed).delay
            }
            // No-human runs and UI tests skip the tap-to-advance gate.
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

    /// Default viewer policy when a UI test hasn't forced an override.
    /// Always pinned to the first seat. Local play has the human at seat 0;
    /// the watch-bots demo has bots in every seat and the user just spectates
    /// from seat 0's perspective. There is no pass-the-device mode.
    private func defaultViewerPolicy(for players: [PlayerID]) -> ViewerPolicy {
        .pinned(players.first ?? PlayerID("player"))
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

/// Single seat in the lobby's local-table roster. Folds the seat's
/// human/bot kind into the same struct as its name so the two can never
/// drift — a previous bug where a bot-seat index pointed at a non-existent
/// row, or where growing the table silently created a *human* seat, is
/// not representable in this model.
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
    /// Stock seat names used for fresh rosters. Matrix characters — the
    /// "you" pill on the viewer's seat already marks which one is the human,
    /// so seat 0 carries a real name (Neo) instead of literally "You".
    static let defaultNames = ["Neo", "Morpheus", "Trinity", "Agent Smith"]

    /// Default fresh roster for the given seat count. Seat 0 is the local
    /// human, every other seat starts as a bot — that matches the
    /// "play vs bots" experience users land on by default.
    static func defaults(count: Int) -> [LobbySeat] {
        precondition(count >= 3 && count <= 4, "Preferans only supports 3- or 4-player tables.")
        return (0..<count).map { index in
            LobbySeat(
                name: defaultNames[index],
                kind: index == 0 ? .human : .bot
            )
        }
    }

    /// Roster used by the Quick-play CTA. Always 3 seats, 1 human + 2 bots.
    static func quickPlayVsBots() -> [LobbySeat] {
        defaults(count: 3)
    }

    /// All-bot roster for a spectator/demo table. The lobby bypasses the
    /// normal "one human" validation only for this explicit preset.
    static func demoBots(count: Int) -> [LobbySeat] {
        defaults(count: count).map { seat in
            LobbySeat(id: seat.id, name: seat.name, kind: .bot)
        }
    }

    /// Resize an existing roster to `count` seats while keeping existing
    /// rows intact (preserving any user edits to names / bot toggles).
    /// Newly-added seats default to bot, matching the bot-by-default
    /// roster used by `defaults`.
    static func resize(_ existing: [LobbySeat], to count: Int) -> [LobbySeat] {
        precondition(count >= 3 && count <= 4, "Preferans only supports 3- or 4-player tables.")
        if existing.count == count { return existing }
        if count < existing.count {
            return Array(existing.prefix(count))
        }
        var resized = existing
        for index in existing.count..<count {
            resized.append(LobbySeat(
                name: defaultNames[index],
                kind: .bot
            ))
        }
        return resized
    }
}

extension Array where Element == LobbySeat {
    /// One-line caption for the lobby (e.g. "1 human · 2 bots"). The two
    /// halves are localized independently (so each language gets its own
    /// plural rules) and joined with a language-neutral middot separator.
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

    /// Why this roster can't start a table, or `nil` when it's ready.
    /// Drives the inline validation message and disables the Start button.
    /// The seat kinds are locked by the lobby's factory methods (seat 0 is
    /// always human for "Sit down", every seat is bot for "Watch bots"), so
    /// only the user-editable name fields need validating.
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

// MARK: - Convention legend sheet

/// Tap target on the lobby hero's house-name tagline. Spells out the
/// mapping from our private rename (Одеса / Wien / Θεσσαλονίκη / Крути)
/// to the names a wider Preferans audience would recognize
/// (Sochi / Leningrad / Rostov / Stalingrad). The hover/VoiceOver hints
/// on the tagline pills cover the same ground in one line; this sheet is
/// the iPhone fallback for devices without pointer hover.
struct ConventionLegendSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct Entry: Identifiable {
        let id: String
        let house: String
        let standard: LocalizedStringKey
        let tradition: LocalizedStringKey
        let summary: LocalizedStringKey
    }

    private let entries: [Entry] = [
        Entry(id: "odesa",
              house: "Одеса",
              standard: "convention.odesa.standard",
              tradition: "convention.odesa.tradition",
              summary: "convention.odesa.summary"),
        Entry(id: "wien",
              house: "Wien",
              standard: "convention.wien.standard",
              tradition: "convention.wien.tradition",
              summary: "convention.wien.summary"),
        Entry(id: "thessaloniki",
              house: "Θεσσαλονίκη",
              standard: "convention.thessaloniki.standard",
              tradition: "convention.thessaloniki.tradition",
              summary: "convention.thessaloniki.summary"),
        Entry(id: "kruty",
              house: "Крути",
              standard: "convention.kruty.standard",
              tradition: "convention.kruty.tradition",
              summary: "convention.kruty.summary")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("convention.legend.intro")
                        .font(.callout)
                        .foregroundStyle(TableTheme.inkCreamSoft)

                    VStack(spacing: 10) {
                        ForEach(entries) { entry in
                            entryCard(entry)
                        }
                    }

                    Text("convention.legend.outro")
                        .font(.footnote)
                        .foregroundStyle(TableTheme.inkCreamDim)
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .feltBackground()
            .navigationTitle(Text("convention.legend.title"))
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { dismiss() }) {
                        Text("Done").foregroundStyle(TableTheme.goldBright)
                    }
                }
            }
        }
        .accessibilityIdentifier(UIIdentifiers.conventionLegendSheet)
    }

    private func entryCard(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: entry.house)
                    .font(.title3.bold())
                    .foregroundStyle(TableTheme.goldBright)
                Text("convention.legend.replaces")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(TableTheme.inkCreamDim)
                Text(entry.standard)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TableTheme.inkCream)
                Spacer(minLength: 0)
                Text(entry.tradition)
                    .font(.caption2)
                    .foregroundStyle(TableTheme.inkCreamSoft)
            }
            Text(entry.summary)
                .font(.footnote)
                .foregroundStyle(TableTheme.inkCream)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(TableTheme.gold.opacity(0.22), lineWidth: 0.5)
        )
    }
}
