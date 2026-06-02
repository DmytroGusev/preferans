import SwiftUI
import PreferansEngine
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

public struct LobbyView: View {
    @StateObject private var viewModel = LobbyViewModel()
    @State private var showingSettings = false
    @State private var showingWatchBotsConfirm = false
    @State private var showingConventionLegend = false
    @State private var didRunOnlineHarness = false

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
                    lobbyContent
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
        if TestHarness.autoCreateOnlineRoom(in: args) {
            didRunOnlineHarness = true
            viewModel.startCloudflareOnlineRoom()
        } else if let roomCode = TestHarness.autoJoinOnlineRoomCode(from: args) {
            didRunOnlineHarness = true
            viewModel.onlineJoinRoomCode = roomCode
            viewModel.joinCloudflareOnlineRoom()
        }
    }

    private var lobbyContent: some View {
        ScrollView {
            VStack(spacing: 18) {
                hero
                onlineRoomCard
                localTableCard
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
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier(UIIdentifiers.lobbyError)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .feltBackground()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.screenLobby)
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
                botCountStepper

                VStack(spacing: 8) {
                    ForEach(Array(viewModel.seats.enumerated()), id: \.element.id) { index, _ in
                        seatRow(index: index)
                    }
                }
                legacySeatCountAccessibilityButtons

                botSpeedPicker

                if let validation = viewModel.seats.validationError {
                    Text(validation)
                        .font(.caption)
                        .foregroundStyle(.orange)
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
                Button { viewModel.quickPlayVsBots() } label: { Color.clear }
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
                    .allowsHitTesting(true)
                    .accessibilityIdentifier(UIIdentifiers.lobbyQuickPlayVsBots)

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

    /// Online play, reorganized so the three intents that used to be jumbled
    /// in one "Invite to game" card now read as distinct, labeled steps:
    /// who you are (identity) → host a new table → or join an existing one.
    private var onlineRoomCard: some View {
        card(title: "Play online", icon: "person.2.wave.2.fill") {
            VStack(spacing: 16) {
                onlineAccountControl

                VStack(spacing: 8) {
                    onlineSectionLabel("Host a table")
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
                            Text("Create invite link")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.feltPrimary)
                    .controlSize(.large)
                    .disabled(
                        viewModel.seats.validationError != nil
                            || viewModel.isOnlineRoomLoading
                    )
                    .accessibilityIdentifier(UIIdentifiers.onlineCreateRoom)

                    Text("You get a link and code to share — friends join from their own devices.")
                        .font(.caption2)
                        .foregroundStyle(TableTheme.inkCreamDim)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                onlineOrJoinDivider

                VStack(spacing: 8) {
                    onlineSectionLabel("Join a table")
                    if let pendingCode = viewModel.pendingJoinRoomCode {
                        readyToJoinRow(code: pendingCode)
                    }
                    HStack(spacing: 8) {
                        TextField(
                            "Paste link or code",
                            text: $viewModel.onlineJoinRoomCode,
                            prompt: Text("Paste link or code")
                                .foregroundStyle(TableTheme.inkCreamDim)
                        )
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
                        .foregroundStyle(
                            viewModel.pendingJoinRoomCode != nil
                                ? TableTheme.goldBright
                                : TableTheme.inkCreamDim
                        )
                        .disabled(
                            viewModel.isOnlineRoomLoading
                                || viewModel.pendingJoinRoomCode == nil
                        )
                        .accessibilityLabel("Join table")
                        .accessibilityIdentifier(UIIdentifiers.onlineJoinRoom)
                    }
                }

                hiddenLocalTestRoomButton
            }
        }
    }

    private func onlineSectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(TableTheme.gold)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var onlineOrJoinDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(TableTheme.gold.opacity(0.22))
                .frame(height: 0.5)
                .frame(maxWidth: .infinity)
            Text("or")
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1.0)
                .foregroundStyle(TableTheme.inkCreamDim)
                .fixedSize()
            Rectangle()
                .fill(TableTheme.gold.opacity(0.22))
                .frame(height: 0.5)
                .frame(maxWidth: .infinity)
        }
    }

    /// Prominent, in-context affordance shown the moment a valid invite code is
    /// present (pasted or arrived via a `/join/<code>` link) — replacing the old
    /// behavior where the code silently dropped into the text field with no cue.
    private func readyToJoinRow(code: String) -> some View {
        Button {
            viewModel.joinCloudflareOnlineRoom()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "ticket.fill")
                    .foregroundStyle(TableTheme.goldBright)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Join table \(code)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TableTheme.inkCream)
                    Text("Tap to take a seat")
                        .font(.caption2)
                        .foregroundStyle(TableTheme.inkCreamDim)
                }
                Spacer(minLength: 0)
                if viewModel.isOnlineRoomLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(TableTheme.goldBright)
                }
            }
            .padding(12)
            .background(TableTheme.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(TableTheme.gold.opacity(0.40), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isOnlineRoomLoading)
    }

    @ViewBuilder
    private var onlineAccountControl: some View {
        if let registeredOnlineAccount = viewModel.registeredOnlineAccount {
            identityStatusRow(
                icon: "person.crop.circle.badge.checkmark",
                title: String(localized: "Signed in as \(registeredOnlineAccount.displayName)"),
                trailingAction: {
                    Button {
                        viewModel.clearRegisteredOnlineAccount()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TableTheme.inkCreamSoft)
                    .accessibilityLabel("Use anonymous identity")
                }
            )
        } else {
            #if canImport(AuthenticationServices)
            HStack {
                SignInWithAppleButton(
                    .signIn,
                    onRequest: configureAppleSignIn,
                    onCompletion: handleAppleSignIn
                )
                .signInWithAppleButtonStyle(.black)
                .frame(width: 190, height: 36)
                .clipShape(Capsule())
                .accessibilityIdentifier(UIIdentifiers.onlineRegisterWithApple)
                Spacer()
            }
            #endif
        }
    }

    @ViewBuilder
    private var hiddenLocalTestRoomButton: some View {
        #if DEBUG
        Button { viewModel.startInMemoryOnlineRoom() } label: { Color.clear }
            .frame(width: 1, height: 1)
            .opacity(0.001)
            .allowsHitTesting(true)
            .accessibilityIdentifier(UIIdentifiers.onlineCreateTestRoom)
        #endif
    }

    private func identityStatusRow<Trailing: View>(
        icon: String,
        title: String,
        @ViewBuilder trailingAction: () -> Trailing
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(TableTheme.goldBright)
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(TableTheme.inkCream)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            trailingAction()
        }
        .padding(10)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
    }

    private func identityStatusRow(icon: String, title: String) -> some View {
        identityStatusRow(icon: icon, title: title) {
            EmptyView()
        }
    }

    #if canImport(AuthenticationServices)
    private func configureAppleSignIn(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName]
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                viewModel.errorText = String(localized: "Apple sign-in did not return an app account.")
                return
            }
            viewModel.completeAppleRegistration(
                userID: credential.user,
                fullName: credential.fullName
            )
        case let .failure(error):
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                return
            }
            viewModel.errorText = error.localizedDescription
        }
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
