import SwiftUI
import PreferansEngine
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(UIKit)
import UIKit
#endif

struct LobbyLayoutPolicy: Equatable {
    var isRegularWidth: Bool
    var usesAccessibilityText: Bool
    /// Device idiom is authoritative for tablet-vs-phone chrome. An iPad in
    /// a narrow Split View can report compact width without becoming an
    /// iPhone; its tablet shell should remain recognizable while content
    /// stacks to fit.
    var isPadDevice: Bool = false

    var usesTabletChrome: Bool { isPadDevice || isRegularWidth }
    var usesTwoRegionComposition: Bool {
        isRegularWidth && !usesAccessibilityText
    }
    var stacksModeChoices: Bool {
        usesTabletChrome || usesAccessibilityText
    }
}

public struct LobbyView: View {
    @Environment(\.tableTheme) var theme

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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @StateObject var viewModel = LobbyViewModel()
    @StateObject private var gameLibrary = OnlineGameLibrary()
    @State private var activeSheet: Sheet?
    @State private var showingWatchBotsConfirm = false
    @State private var showingTableOptions = false
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

    var layoutPolicy: LobbyLayoutPolicy {
        LobbyLayoutPolicy(
            isRegularWidth: horizontalSizeClass == .regular,
            usesAccessibilityText: dynamicTypeSize.isAccessibilitySize,
            isPadDevice: isPadDevice
        )
    }

    private var isPadDevice: Bool {
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }

    private var usesTabletLobby: Bool {
        layoutPolicy.usesTabletChrome
    }

    private var usesTwoRegionLobby: Bool {
        layoutPolicy.usesTwoRegionComposition
    }

    private var adaptiveLobbyLayout: AnyLayout {
        if usesTwoRegionLobby {
            AnyLayout(HStackLayout(alignment: .top, spacing: 32))
        } else {
            AnyLayout(VStackLayout(spacing: 18))
        }
    }

    private var adaptiveModeLayout: AnyLayout {
        if layoutPolicy.stacksModeChoices {
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
                                .foregroundStyle(theme.accentStrong)
                                .accessibilityLabel("Settings")
                        }
                        .accessibilityIdentifier(UIIdentifiers.lobbySettingsButton)
                    }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .settings:
                    SettingsScreen {
                        try await viewModel.deleteRegisteredOnlineAccount()
                    }
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
        if TestHarness.autoCreateInMemoryInviteRoom(in: args) {
            didRunOnlineHarness = true
            seedOnlineNameForHarnessIfNeeded()
            viewModel.startInMemoryOnlineRoom(openRemoteSeats: true)
        } else if TestHarness.autoCreateInMemoryRoom(in: args) {
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
                    .frame(maxWidth: usesTwoRegionLobby ? 340 : (usesTabletLobby ? 620 : .infinity))

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
        // status bar and settings button. Navigation chrome follows the theme.
        .themeNavigationChrome()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.lobbyMode == .local { localStartBar }
        }
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


        }
        .padding(usesTabletLobby ? 24 : 0)
        .background {
            if usesTabletLobby {
                RoundedRectangle(cornerRadius: 20)
                    .fill(theme.shade.opacity(0.20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(theme.accent.opacity(0.18), lineWidth: 0.5)
                    )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.lobbyNavigationRegion)
    }

    private var lobbyModeRegion: some View {
        VStack(spacing: 18) {
            if viewModel.lobbyMode == .local {
                localTableCard
            } else {
                LobbyYourGamesSection(
                    viewModel: viewModel,
                    gameLibrary: gameLibrary,
                    onSelectFinishedGame: { activeSheet = .gameSummary($0) }
                )
                onlineSetupCard
            }
            if let infoText = viewModel.infoText {
                Label(infoText, systemImage: "checkmark.seal.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.accentStrong)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier(UIIdentifiers.lobbyInfo)
            }
            if let errorText = viewModel.errorText {
                Text(errorText)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.error)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier(UIIdentifiers.lobbyError)
            }
            conventionsFooterLink
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.lobbyModeRegion)
    }

    /// Hero on the felt: gold suit glyph, large cream title. The house-
    /// convention naming used to dominate this spot; it now lives as a quiet
    /// footer link so the hero leads with "what do you want to do" instead.
    private var hero: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(theme.accent.opacity(0.16))
                    .frame(width: 78, height: 78)
                    .overlay(
                        Circle().strokeBorder(theme.accent.opacity(0.45), lineWidth: 0.75)
                    )
                Image(systemName: "suit.spade.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(theme.accentStrong)
            }
            Text("Preferans")
                .font(.system(.largeTitle, design: theme.style.titleDesign, weight: .bold))
                .foregroundStyle(theme.textPrimary)
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
            .foregroundStyle(isSelected ? theme.onAccent : theme.textPrimary)
            .background(
                isSelected ? theme.accentStrong : theme.shade.opacity(0.22),
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
            .foregroundStyle(theme.accent)
        }
        .buttonStyle(.plain)
        .help("convention.tagline.help")
        .accessibilityHint("convention.tagline.accessibilityHint")
        .accessibilityIdentifier(UIIdentifiers.lobbyHouseConventions)
    }

    private var localStartBar: some View {
        VStack(spacing: 8) {
            if let validation = viewModel.seats.validationError {
                Text(validation)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(theme.warning)
                    .accessibilityIdentifier(UIIdentifiers.lobbyValidationError)
            } else {
                (Text("\(viewModel.seats.count) players")
                 + Text(verbatim: " · ")
                 + Text(viewModel.onlineVariant.standardName))
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
                    .accessibilityIdentifier(UIIdentifiers.lobbyStartSummary)
            }
            Button { viewModel.startLocalTable() } label: {
                Label("Sit down", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 28)
            }
            .buttonStyle(.feltPrimary)
            .disabled(viewModel.seats.validationError != nil)
            .accessibilityIdentifier(UIIdentifiers.lobbyStartLocalTable)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: 540)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .feltBand()
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
                DisclosureGroup(isExpanded: $showingTableOptions) {
                    VStack(spacing: 16) {
                        variantControls
                        botSpeedPicker
                        pulkaLimitPicker
                        raspasyControls
                    }
                    .padding(.top, 12)
                } label: {
                    Label("Table options", systemImage: "slider.horizontal.3")
                        .font(.headline)
                        .foregroundStyle(theme.textPrimary)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier(UIIdentifiers.lobbyTableOptions)
                }
                .tint(theme.accent)

                // Spectator-only "watch bots" lives below the roster as a
                // secondary affordance. The main "Sit down" CTA starts from
                // the current local roster.
                Button {
                    showingWatchBotsConfirm = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "eye.fill")
                            .foregroundStyle(theme.accentStrong)
                        Text("Watch bots play")
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(theme.textSecondary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(theme.shade.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
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
                    .foregroundStyle(theme.textPrimary)
            } icon: {
                Image(systemName: "cpu")
                    .foregroundStyle(theme.accentStrong)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                viewModel.removeBot()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.canRemoveBot ? theme.accentStrong : theme.textMuted)
            .disabled(!viewModel.canRemoveBot)
            .accessibilityLabel("Remove bot")
            .accessibilityIdentifier(UIIdentifiers.lobbyRemoveBot)

            Button {
                viewModel.addBot()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(viewModel.canAddBot ? theme.accentStrong : theme.textMuted)
            .disabled(!viewModel.canAddBot)
            .accessibilityLabel("Add bot")
            .accessibilityIdentifier(UIIdentifiers.lobbyAddBot)
        }
        .padding(10)
        .background(theme.shade.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
    }

    private func seatRow(index: Int) -> some View {
        let profile = viewModel.seats[index].botProfile
        let isBot = profile != nil
        let isViewer = index == 0 && !isBot
        return HStack(spacing: 10) {
            Image(systemName: isBot ? "cpu" : "person.crop.circle.fill")
                .foregroundStyle(isBot ? theme.accent : theme.accentStrong)
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                TextField("Seat \(index + 1)", text: nameBinding(for: index))
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .foregroundStyle(theme.textPrimary)
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
                        .foregroundStyle(theme.accent.opacity(0.9))
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
                    .foregroundStyle(theme.onAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.accentStrong, in: Capsule())
            } else {
                Text("badge.bot")
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(theme.shade.opacity(0.30), in: Capsule())
            }
        }
        .padding(10)
        .background(theme.shade.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
    }

    private var botSpeedPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bot speed")
                .font(.caption.weight(.semibold))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(theme.accent)
            Picker("Bot speed", selection: $viewModel.botSpeed) {
                ForEach(BotMoveSpeed.allCases) { speed in
                    Text(speed.label).tag(speed)
                }
            }
            .modifier(LobbyChoiceControlStyle())
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
                .foregroundStyle(theme.accent)
            Picker(title, selection: $viewModel.pulkaLimit) {
                ForEach(PulkaLimit.allCases) { limit in
                    if usesTableTotal, limit != .custom {
                        Text(verbatim: "\(limit.target * max(1, playerCount))").tag(limit)
                    } else {
                        Text(limit.label).tag(limit)
                    }
                }
            }
            .modifier(LobbyChoiceControlStyle())
            .accessibilityIdentifier(UIIdentifiers.matchPoolTarget)

            if viewModel.pulkaLimit == .custom {
                HStack(spacing: 10) {
                    Image(systemName: "number")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.accentStrong)
                    TextField(
                        customPrompt,
                        value: customTarget,
                        format: .number,
                        prompt: Text(customPrompt).foregroundStyle(theme.textMuted)
                    )
                    .textFieldStyle(.plain)
                    #if canImport(UIKit)
                    .keyboardType(.numberPad)
                    #endif
                    .submitLabel(.done)
                    .foregroundStyle(theme.textPrimary)
                    .accessibilityIdentifier(UIIdentifiers.matchCustomPulkaPerPlayer)
                }
                .padding(10)
                .background(theme.shade.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var raspasyControls: some View {
        // The setup pane can be narrow even on a full-width iPad. Each
        // progression needs the pane's whole width to show distinct values.
        VStack(alignment: .leading, spacing: 12) {
            raspasySetting(
                title: "rules.raspasyPrice",
                selection: $viewModel.raspasyPenaltyProgression,
                choices: [
                    (.flat, "1–1–1"),
                    (.arithmetic, "1–2–3"),
                    (.cappedDouble, "1–2–2"),
                    (.geometric, "1–2–4"),
                ],
                identifier: UIIdentifiers.matchRaspasyPrice
            )
            raspasySetting(
                title: "rules.exitMinimum",
                selection: $viewModel.raspasyExitProgression,
                choices: [
                    (.simple, "6–6–6"),
                    (.constrained, "6–7–7"),
                    (.strict, "6–7–8"),
                ],
                identifier: UIIdentifiers.matchRaspasyExit
            )
        }
    }

    private func raspasySetting<Value: Hashable>(
        title: LocalizedStringKey,
        selection: Binding<Value>,
        choices: [(Value, String)],
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(theme.accent)
            Picker(title, selection: selection) {
                ForEach(Array(choices.enumerated()), id: \.offset) { _, choice in
                    Text(verbatim: choice.1).tag(choice.0)
                }
            }
            .modifier(LobbyChoiceControlStyle())
            .accessibilityIdentifier(identifier)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card<Content: View>(title: LocalizedStringKey, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(theme.accentStrong)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
            }
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.shade.opacity(0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(theme.accent.opacity(0.22), lineWidth: 0.5)
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

/// Long segmented choices stop fitting at accessibility text sizes. Native
/// menus preserve the full option labels and the same selection binding.
struct LobbyChoiceControlStyle: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ViewBuilder
    func body(content: Content) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            content
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        } else {
            content.pickerStyle(.segmented)
        }
    }
}
