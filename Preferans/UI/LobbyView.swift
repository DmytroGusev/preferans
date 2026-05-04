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

    @StateObject private var viewModel = LobbyViewModel()
    @State private var showingMatchmaker = false
    @State private var hasAttemptedSignIn = false
    @State private var showingSettings = false
    @State private var showingWatchBotsConfirm = false
    @State private var showingConventionLegend = false

    public init() {}

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
                if viewModel.localModel == nil && viewModel.onlineSession == nil && viewModel.cloudOnlineSession == nil {
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
                Button("Watch") { viewModel.watchBots() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All three seats will be filled with bots and you'll spectate the match. Your roster will be replaced.")
            }
        }
        .onOpenURL { url in
            viewModel.handleInviteURL(url)
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
                    viewModel.errorText = error.localizedDescription
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
                if let errorText = viewModel.errorText {
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
                    ForEach(Array(viewModel.seats.enumerated()), id: \.element.id) { index, _ in
                        seatRow(index: index)
                    }
                }

                botSpeedPicker

                if let validation = viewModel.seats.validationError {
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
                Button { viewModel.quickPlayVsBots() } label: { Color.clear }
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
                viewModel.startLocalTable()
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
            .disabled(viewModel.seats.validationError != nil)
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
        let isBot = viewModel.seats[index].kind == .bot
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

    private var onlineRoomCard: some View {
        card(title: "Invite room", icon: "link") {
            VStack(spacing: 12) {
                TextField("email@example.test", text: $viewModel.onlineAccountEmail)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .foregroundStyle(TableTheme.inkCream)
                    .padding(10)
                    .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier(UIIdentifiers.onlineAccountEmail)

                Picker("Seat", selection: $viewModel.onlineSeatIndex) {
                    ForEach(Array(viewModel.seats.enumerated()), id: \.element.id) { index, seat in
                        Text(seat.trimmedName.isEmpty ? "Seat \(index + 1)" : seat.trimmedName)
                            .tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier(UIIdentifiers.onlineLocalSeatPicker)

                Button {
                    viewModel.startCloudflareOnlineRoom()
                } label: {
                    HStack {
                        if viewModel.isOnlineRoomLoading {
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
                .disabled(viewModel.seats.validationError != nil || viewModel.isOnlineRoomLoading)
                .accessibilityIdentifier(UIIdentifiers.onlineCreateRoom)

                HStack(spacing: 8) {
                    TextField("Room code", text: $viewModel.onlineJoinRoomCode)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .foregroundStyle(TableTheme.inkCream)
                        .padding(10)
                        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier(UIIdentifiers.onlineJoinRoomCode)

                    Button {
                        viewModel.joinCloudflareOnlineRoom()
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TableTheme.goldBright)
                    .disabled(
                        viewModel.isOnlineRoomLoading
                            || PreferansInviteLink.normalizedRoomCode(viewModel.onlineJoinRoomCode) == nil
                    )
                    .accessibilityLabel("Join table")
                    .accessibilityIdentifier(UIIdentifiers.onlineJoinRoom)
                }

                #if DEBUG
                Button {
                    viewModel.startInMemoryOnlineRoom()
                } label: {
                    HStack {
                        Image(systemName: "testtube.2")
                        Text("Run local test room")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.feltSecondary)
                .disabled(viewModel.seats.validationError != nil || viewModel.isOnlineRoomLoading)
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
        let isSelected = viewModel.seats.count == count
        Button { viewModel.setSeatCount(count) } label: {
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
            get: { viewModel.seats.indices.contains(index) ? viewModel.seats[index].name : "" },
            set: { newValue in
                viewModel.setSeatName(newValue, at: index)
            }
        )
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
