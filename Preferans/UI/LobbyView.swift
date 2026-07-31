import SwiftUI
import PreferansEngine
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

public struct LobbyView: View {
    private enum Sheet: Identifiable {
        case settings
        case conventionLegend
        case gameSummary(OnlineGameSummary)

        var id: String {
            switch self {
            case .settings: return "settings"
            case .conventionLegend: return "conventionLegend"
            case let .gameSummary(game): return "gameSummary:\(game.id)"
            }
        }
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// The invisible 1×1 automation affordances exist only under XCUITest —
    /// in a shipping build they were VoiceOver-reachable unlabeled buttons
    /// that could start a real table or online room.
    let isUIAutomation = TestHarness.isUIAutomation()

    @StateObject var viewModel = LobbyViewModel()
    @StateObject private var gameLibrary = OnlineGameLibrary()
    @State private var activeSheet: Sheet?
    @State private var showingWatchBotsConfirm = false
    @State private var didRunOnlineHarness = false
    @State var appleSignInNonce: String?

    public init() {}

    /// Re-fetches "Your games" whenever the player switches into online mode or
    /// their account changes. Returning from a finished/left game re-creates the
    /// lobby content, which also re-runs the `.task`, so the list stays fresh.
    private var onlineGamesRefreshKey: String {
        viewModel.lobbyMode == .online
            ? "online:\(viewModel.currentOnlineAccountID ?? "anonymous-none")"
            : "local"
    }

    private var usesTabletLobby: Bool {
        horizontalSizeClass == .regular
    }

    private var adaptiveLobbyLayout: AnyLayout {
        if usesTabletLobby {
            AnyLayout(HStackLayout(alignment: .top, spacing: 32))
        } else {
            AnyLayout(VStackLayout(spacing: 18))
        }
    }

    private var adaptiveModeLayout: AnyLayout {
        if usesTabletLobby {
            AnyLayout(VStackLayout(spacing: 10))
        } else {
            AnyLayout(HStackLayout(spacing: 8))
        }
    }

    public var body: some View {
        NavigationStack {
            Group {
                if let localModel = viewModel.localModel {
                    LocalGameScreen(
                        model: localModel,
                        onLeaveTable: { viewModel.localModel = nil },
                        onRematch: { viewModel.startLocalTable() }
                    )
                } else if let onlineSession = viewModel.onlineSession {
                    OnlineRoomGameScreen(
                        coordinator: onlineSession.localCoordinator,
                        roomCode: onlineSession.roomCode,
                        onLeaveTable: { viewModel.leaveOnlineRoom() }
                    )
                } else if let cloudOnlineSession = viewModel.cloudOnlineSession {
                    OnlineRoomGameScreen(
                        coordinator: cloudOnlineSession.localCoordinator,
                        roomCode: cloudOnlineSession.roomCode,
                        inviteURL: cloudOnlineSession.inviteURL,
                        onLeaveTable: { viewModel.leaveOnlineRoom() }
                    )
                } else {
                    lobbyContent
                }
            }
            .toolbar {
                if viewModel.localModel == nil && viewModel.onlineSession == nil && viewModel.cloudOnlineSession == nil {
                    ToolbarItem(placement: .automatic) {
                        Button { activeSheet = .settings } label: {
                            Image(systemName: "gearshape.fill")
                                .foregroundStyle(TableTheme.goldBright)
                                .accessibilityLabel("Settings")
                        }
                        .accessibilityIdentifier(UIIdentifiers.lobbySettingsButton)
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .settings:
                    SettingsScreen()
                case .conventionLegend:
                    ConventionLegendSheet(initialVariant: viewModel.onlineVariant)
                case let .gameSummary(game):
                    OnlineGameSummarySheet(game: game)
                }
            }
            .confirmationDialog(
                "Watch the bots play?",
                isPresented: $showingWatchBotsConfirm,
                titleVisibility: .visible
            ) {
                Button("Watch") { viewModel.watchBots() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All three seats will be filled with bots and you'll spectate the match. Your roster will be replaced.")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.appRoot)
        .onAppear {
            runOnlineHarnessIfNeeded()
        }
        .onOpenURL { url in
            viewModel.handleInviteURL(url)
        }
    }

    private func runOnlineHarnessIfNeeded() {
        guard !didRunOnlineHarness else { return }
        let args = ProcessInfo.processInfo.arguments
        if TestHarness.autoCreateInMemoryRoom(in: args) {
            didRunOnlineHarness = true
            seedOnlineNameForHarnessIfNeeded()
            viewModel.startInMemoryOnlineRoom()
        } else if TestHarness.autoCreateOnlineRoom(in: args) {
            didRunOnlineHarness = true
            seedOnlineNameForHarnessIfNeeded()
            viewModel.startCloudflareOnlineRoom()
        } else if let roomCode = TestHarness.autoJoinOnlineRoomCode(from: args) {
            didRunOnlineHarness = true
            seedOnlineNameForHarnessIfNeeded()
            viewModel.onlineJoinRoomCode = roomCode
            viewModel.joinCloudflareOnlineRoom()
        }
    }

    private func seedOnlineNameForHarnessIfNeeded() {
        guard viewModel.onlineIdentityValidationError != nil else { return }
        viewModel.setOnlineDisplayName(String(localized: "Player"))
    }

    private var lobbyContent: some View {
        ScrollView {
            adaptiveLobbyLayout {
                lobbyNavigationRegion
                    .frame(maxWidth: usesTabletLobby ? 340 : .infinity)

                lobbyModeRegion
                    .frame(maxWidth: usesTabletLobby ? 620 : .infinity)
            }
            .padding(.horizontal, usesTabletLobby ? 36 : 18)
            .padding(.top, usesTabletLobby ? 44 : 18)
            .padding(.bottom, 24)
            .frame(maxWidth: usesTabletLobby ? 1080 : 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        // The online card is a long form with two text fields — let a drag
        // put the keyboard away instead of trapping it on screen.
        .scrollDismissesKeyboard(.interactively)
        .feltBackground()
        // Keep scrolled form controls from becoming visual noise behind the
        // status bar and settings button. The lobby is always dark felt, so
        // the navigation chrome also owns a dark, opaque contrast surface.
        .lobbyNavigationChrome()
        .task(id: onlineGamesRefreshKey) {
            guard viewModel.lobbyMode == .online else { return }
            await gameLibrary.refresh(sessionToken: viewModel.onlineAccountSessionToken)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.screenLobby)
    }

    private var lobbyNavigationRegion: some View {
        VStack(spacing: 18) {
            hero
            modeSegment

            if usesTabletLobby {
                VStack(alignment: .leading, spacing: 8) {
                    Label("A complete table at a glance", systemImage: "rectangle.split.2x1")
                        .font(.headline)
                        .foregroundStyle(TableTheme.inkCream)
                    Text("Choose how to play here, then set up the table alongside it. Your current game always takes over the full screen.")
                        .font(.subheadline)
                        .foregroundStyle(TableTheme.inkCreamSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(usesTabletLobby ? 24 : 0)
        .background {
            if usesTabletLobby {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(TableTheme.gold.opacity(0.18), lineWidth: 0.5)
                    )
            }
        }
    }

    private var lobbyModeRegion: some View {
        VStack(spacing: 18) {
            if viewModel.lobbyMode == .local {
                localTableCard
                if isUIAutomation { onlineHiddenAffordances }
            } else {
                LobbyYourGamesSection(
                    viewModel: viewModel,
                    gameLibrary: gameLibrary,
                    onSelectFinishedGame: { activeSheet = .gameSummary($0) }
                )
                onlineSetupCard
                if isUIAutomation { localHiddenAffordances }
            }
            if let infoText = viewModel.infoText {
                Label(infoText, systemImage: "checkmark.seal.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(TableTheme.goldBright)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier(UIIdentifiers.lobbyInfo)
            }
            if let errorText = viewModel.errorText {
                Text(errorText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(TableTheme.errorInk)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier(UIIdentifiers.lobbyError)
            }
            conventionsFooterLink
        }
    }

    /// Hero on the felt: gold suit glyph, large cream title. The house-
    /// convention naming used to dominate this spot; it now lives as a quiet
    /// footer link so the hero leads with "what do you want to do" instead.
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
        }
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    /// The single top-level choice: play a quick local game against bots, or
    /// set up an online room with friends. Picking a mode swaps the composition
    /// card below — the two flows no longer share any state.
    private var modeSegment: some View {
        adaptiveModeLayout {
            modeButton(.local, title: "Play with bots", icon: "cpu",
                       identifier: UIIdentifiers.lobbyModeLocal)
            modeButton(.online, title: "Play online", icon: "person.2.wave.2.fill",
                       identifier: UIIdentifiers.lobbyModeOnline)
        }
    }

    private func modeButton(
        _ mode: LobbyViewModel.LobbyMode,
        title: LocalizedStringKey,
        icon: String,
        identifier: String
    ) -> some View {
        let isSelected = viewModel.lobbyMode == mode
        return Button {
            viewModel.lobbyMode = mode
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? TableTheme.feltDeep : TableTheme.inkCream)
            .background(
                isSelected ? TableTheme.goldBright : Color.black.opacity(0.22),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Demoted house-convention entry point. The names that used to crowd the
    /// hero now sit quietly at the foot of the lobby; tapping still opens the
    /// full legend sheet.
    private var conventionsFooterLink: some View {
        Button {
            activeSheet = .conventionLegend
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                Text("rules.reference.title")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(TableTheme.gold)
        }
        .buttonStyle(.plain)
        .help("convention.tagline.help")
        .accessibilityHint("convention.tagline.accessibilityHint")
        .accessibilityIdentifier(UIIdentifiers.lobbyHouseConventions)
    }

    /// Test-only mirror keeping the online Create/Join identifiers in the
    /// accessibility tree while the lobby is showing the *local* card. Uses the
    /// same 1×1 / near-zero-opacity idiom as the other hidden affordances so the
    /// "all automation roots reachable at launch" contract holds in either mode.
    private var onlineHiddenAffordances: some View {
        VStack(spacing: 0) {
            Button { viewModel.startCloudflareOnlineRoom() } label: { Color.clear }
                .accessibilityIdentifier(UIIdentifiers.onlineCreateRoom)
            TextField("", text: $viewModel.onlineJoinRoomCode)
                .accessibilityIdentifier(UIIdentifiers.onlineJoinRoomCode)
            Button { viewModel.joinCloudflareOnlineRoom() } label: { Color.clear }
                .accessibilityIdentifier(UIIdentifiers.onlineJoinRoom)
        }
        .frame(width: 1, height: 1)
        .opacity(0.001)
        .allowsHitTesting(true)
    }

    /// Mirror of the local automation roots, kept alive while the *online* card
    /// is showing. Symmetric counterpart to `onlineHiddenAffordances`.
    private var localHiddenAffordances: some View {
        VStack(spacing: 0) {
            Button { viewModel.startLocalTable() } label: { Color.clear }
                .accessibilityIdentifier(UIIdentifiers.lobbyStartLocalTable)
            Button { viewModel.quickPlayVsBots() } label: { Color.clear }
                .accessibilityIdentifier(UIIdentifiers.lobbyQuickPlayVsBots)
            Button { showingWatchBotsConfirm = true } label: { Color.clear }
                .accessibilityIdentifier(UIIdentifiers.lobbyWatchBots)
            Button { viewModel.addBot() } label: { Color.clear }
                .accessibilityIdentifier(UIIdentifiers.lobbyAddBot)
            Button { viewModel.removeBot() } label: { Color.clear }
                .accessibilityIdentifier(UIIdentifiers.lobbyRemoveBot)
            Button { viewModel.setSeatCount(3) } label: { Color.clear }
                .accessibilityIdentifier(UIIdentifiers.lobbyPlayerCountThree)
            Button { viewModel.setSeatCount(4) } label: { Color.clear }
                .accessibilityIdentifier(UIIdentifiers.lobbyPlayerCountFour)
            TextField("", text: nameBinding(for: 0))
                .accessibilityIdentifier(UIIdentifiers.lobbyPlayerNameField(index: 0))
            Picker("", selection: $viewModel.botSpeed) {
                ForEach(BotMoveSpeed.allCases) { speed in
                    Text(speed.label).tag(speed)
                }
            }
            .accessibilityIdentifier(UIIdentifiers.lobbyBotSpeedPicker)
        }
        .frame(width: 1, height: 1)
        .opacity(0.001)
        .allowsHitTesting(true)
    }

    private var localTableCard: some View {
        card(title: "At this table", icon: "person.3.fill") {
            VStack(spacing: 14) {
                botCountStepper

                VStack(spacing: 8) {
                    ForEach(Array(viewModel.seats.enumerated()), id: \.element.id) { index, _ in
                        seatRow(index: index)
                    }
                }
                if isUIAutomation { legacySeatCountAccessibilityButtons }

                variantControls
                botSpeedPicker
                pulkaLimitPicker

                if let validation = viewModel.seats.validationError {
                    Text(validation)
                        .font(.caption)
                        .foregroundStyle(TableTheme.warningInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier(UIIdentifiers.lobbyValidationError)
                }

                Button {
                    viewModel.startLocalTable()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Sit down")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.feltPrimary)
                .controlSize(.large)
                .disabled(viewModel.seats.validationError != nil)
                .accessibilityIdentifier(UIIdentifiers.lobbyStartLocalTable)

                // Hidden test-only affordance. The visible quick-play CTA was
                // folded into "Sit down" (which already starts a table with
                // the current roster), but UI tests still tap this identifier
                // to land on a 1-human + 2-bot table from a clean lobby.
                // SwiftUI elides zero-frame / fully-transparent views from the
                // accessibility tree, which is why this uses a 1×1 frame and
                // a near-zero (but non-zero) opacity.
                if isUIAutomation {
                    Button { viewModel.quickPlayVsBots() } label: { Color.clear }
                        .frame(width: 1, height: 1)
                        .opacity(0.001)
                        .allowsHitTesting(true)
                        .accessibilityIdentifier(UIIdentifiers.lobbyQuickPlayVsBots)
                }

                // Spectator-only "watch bots" lives below the roster as a
                // secondary affordance. The main "Sit down" CTA starts from
                // the current local roster.
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

    private var botCountStepper: some View {
        HStack(spacing: 10) {
            Label {
                Text("\(viewModel.botCount) bots")
                    .font(.headline)
                    .foregroundStyle(TableTheme.inkCream)
            } icon: {
                Image(systemName: "cpu")
                    .foregroundStyle(TableTheme.goldBright)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                viewModel.removeBot()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.canRemoveBot ? TableTheme.goldBright : TableTheme.inkCreamDim)
            .disabled(!viewModel.canRemoveBot)
            .accessibilityLabel("Remove bot")
            .accessibilityIdentifier(UIIdentifiers.lobbyRemoveBot)

            Button {
                viewModel.addBot()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.canAddBot ? TableTheme.goldBright : TableTheme.inkCreamDim)
            .disabled(!viewModel.canAddBot)
            .accessibilityLabel("Add bot")
            .accessibilityIdentifier(UIIdentifiers.lobbyAddBot)
        }
        .padding(10)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
    }

    private var legacySeatCountAccessibilityButtons: some View {
        HStack(spacing: 0) {
            Button { viewModel.setSeatCount(3) } label: { Color.clear }
                .accessibilityIdentifier(UIIdentifiers.lobbyPlayerCountThree)
            Button { viewModel.setSeatCount(4) } label: { Color.clear }
                .accessibilityIdentifier(UIIdentifiers.lobbyPlayerCountFour)
        }
        .frame(width: 1, height: 1)
        .opacity(0.001)
        .allowsHitTesting(true)
    }

    private func seatRow(index: Int) -> some View {
        let profile = viewModel.seats[index].botProfile
        let isBot = profile != nil
        let isViewer = index == 0 && !isBot
        return HStack(spacing: 10) {
            Image(systemName: isBot ? "cpu" : "person.crop.circle.fill")
                .foregroundStyle(isBot ? TableTheme.gold : TableTheme.goldBright)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                TextField("Seat \(index + 1)", text: nameBinding(for: index))
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .foregroundStyle(TableTheme.inkCream)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(UIIdentifiers.lobbyPlayerNameField(index: index))

                if let profile {
                    Menu {
                        Picker("Strength", selection: botDifficultyBinding(for: index)) {
                            ForEach(BotDifficulty.allCases, id: \.self) { difficulty in
                                Text(difficulty.label).tag(difficulty)
                            }
                        }
                        Picker("Style", selection: botTemperamentBinding(for: index)) {
                            ForEach(BotTemperament.allCases, id: \.self) { temperament in
                                Text(temperament.label).tag(temperament)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(profile.temperament.label)
                            Text("·")
                            Text(profile.difficulty.label)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(TableTheme.gold.opacity(0.9))
                    }
                    .accessibilityLabel("Bot profile")
                    .accessibilityValue("\(profile.temperament.rawValue), \(profile.difficulty.rawValue)")
                    .accessibilityIdentifier(UIIdentifiers.lobbyBotProfile(index: index))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isViewer {
                Text("badge.you")
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(TableTheme.feltDeep)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(TableTheme.goldBright, in: Capsule())
            } else {
                Text("badge.bot")
                    .font(.caption2.weight(.bold))
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
            Picker("Bot speed", selection: $viewModel.botSpeed) {
                ForEach(BotMoveSpeed.allCases) { speed in
                    Text(speed.label).tag(speed)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(UIIdentifiers.lobbyBotSpeedPicker)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var pulkaLimitPicker: some View {
        let usesTableTotal = viewModel.onlineVariant.poolClosure == .tableTotal
        let playerCount = viewModel.lobbyMode == .online
            ? viewModel.onlineComposition.count
            : viewModel.seats.count
        let title: LocalizedStringKey = usesTableTotal ? "Table pool total" : "Pulka per player"
        let customPrompt: LocalizedStringKey = usesTableTotal ? "Table total" : "Per player"
        let customTarget = Binding<Int>(
            get: {
                usesTableTotal
                    ? viewModel.customPulkaTableTotal
                    : viewModel.customPulkaPerPlayer
            },
            set: { value in
                if usesTableTotal {
                    viewModel.customPulkaTableTotal = value
                } else {
                    viewModel.customPulkaPerPlayer = value
                }
            }
        )

        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(TableTheme.gold)
            Picker(title, selection: $viewModel.pulkaLimit) {
                ForEach(PulkaLimit.allCases) { limit in
                    if usesTableTotal, limit != .custom {
                        Text(verbatim: "\(limit.target * max(1, playerCount))").tag(limit)
                    } else {
                        Text(limit.label).tag(limit)
                    }
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(UIIdentifiers.matchPoolTarget)

            if viewModel.pulkaLimit == .custom {
                HStack(spacing: 10) {
                    Image(systemName: "number")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TableTheme.goldBright)
                    TextField(
                        customPrompt,
                        value: customTarget,
                        format: .number,
                        prompt: Text(customPrompt).foregroundStyle(TableTheme.inkCreamDim)
                    )
                    .textFieldStyle(.plain)
                    #if canImport(UIKit)
                    .keyboardType(.numberPad)
                    #endif
                    .submitLabel(.done)
                    .foregroundStyle(TableTheme.inkCream)
                    .accessibilityIdentifier(UIIdentifiers.matchCustomPulkaPerPlayer)
                }
                .padding(10)
                .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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

    private func nameBinding(for index: Int) -> Binding<String> {
        Binding(
            get: { viewModel.seats.indices.contains(index) ? viewModel.seats[index].name : "" },
            set: { newValue in
                viewModel.setSeatName(newValue, at: index)
            }
        )
    }

    private func botDifficultyBinding(for index: Int) -> Binding<BotDifficulty> {
        Binding(
            get: {
                guard viewModel.seats.indices.contains(index) else { return .seasoned }
                return viewModel.seats[index].botProfile?.difficulty ?? .seasoned
            },
            set: { difficulty in
                guard viewModel.seats.indices.contains(index),
                      var profile = viewModel.seats[index].botProfile else { return }
                profile.difficulty = difficulty
                viewModel.setBotProfile(profile, at: index)
            }
        )
    }

    private func botTemperamentBinding(for index: Int) -> Binding<BotTemperament> {
        Binding(
            get: {
                guard viewModel.seats.indices.contains(index) else { return .adaptive }
                return viewModel.seats[index].botProfile?.temperament ?? .adaptive
            },
            set: { temperament in
                guard viewModel.seats.indices.contains(index),
                      var profile = viewModel.seats[index].botProfile else { return }
                profile.temperament = temperament
                viewModel.setBotProfile(profile, at: index)
            }
        )
    }
}

private extension View {
    @ViewBuilder
    func lobbyNavigationChrome() -> some View {
        #if os(iOS)
        self
            .toolbarBackground(TableTheme.feltDeep, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        #else
        self
        #endif
    }
}
