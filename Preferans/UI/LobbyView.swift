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
    @State private var seats: [LobbySeat] = LobbySeat.defaults(count: 3)
    @State private var botSpeed: BotMoveSpeed = .normal
    @State private var errorText: String?
    @State private var showingMatchmaker = false
    @State private var hasAttemptedSignIn = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if let localModel {
                    LocalGameScreen(model: localModel)
                } else {
                    #if canImport(GameKit) && canImport(UIKit)
                    if let projection = online.projection {
                        ProjectionGameScreen(projection: projection, eventLog: online.eventLog, onSend: online.send)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Leave") { online.detach() }
                                }
                            }
                    } else {
                        lobbyContent
                    }
                    #else
                    lobbyContent
                    #endif
                }
            }
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
            VStack(spacing: 28) {
                hero

                localTableCard

                #if canImport(GameKit) && canImport(UIKit)
                onlineCard
                #endif

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier(UIIdentifiers.lobbyError)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        #if canImport(UIKit)
        .background(Color(.systemGroupedBackground))
        #endif
    }

    private var hero: some View {
        VStack(spacing: 6) {
            Image(systemName: "suit.spade.fill")
                .font(.system(size: 38))
                .foregroundStyle(LinearGradient(
                    colors: [Color(red: 0.13, green: 0.40, blue: 0.27), Color(red: 0.10, green: 0.30, blue: 0.20)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            Text("Preferans")
                .font(.largeTitle.bold())
                .accessibilityIdentifier(UIIdentifiers.lobbyTitle)
            Text("Classic Sochi & Rostov rules")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var localTableCard: some View {
        card(title: "Local table", icon: "person.3.fill") {
            VStack(spacing: 14) {
                Button {
                    quickPlayVsBots()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                        Text("Quick play vs bots")
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(UIIdentifiers.lobbyQuickPlayVsBots)

                Text(seats.rosterSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    seatCountButton(count: 3, id: UIIdentifiers.lobbyPlayerCountThree)
                    seatCountButton(count: 4, id: UIIdentifiers.lobbyPlayerCountFour)
                }

                VStack(spacing: 8) {
                    ForEach(Array(seats.enumerated()), id: \.element.id) { index, _ in
                        seatRow(index: index)
                    }
                }

                if seats.contains(where: { $0.kind == .bot }) {
                    botSpeedPicker
                }

                if let validation = seats.validationError {
                    Text(validation)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier(UIIdentifiers.lobbyValidationError)
                }

                Button {
                    startLocalTable()
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start table")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(seats.validationError != nil)
                .accessibilityIdentifier(UIIdentifiers.lobbyStartLocalTable)
            }
        }
    }

    private func seatRow(index: Int) -> some View {
        let isBot = seats[index].kind == .bot
        return HStack(spacing: 10) {
            Image(systemName: isBot ? "cpu" : "person.crop.circle")
                .foregroundStyle(isBot ? Color.accentColor : .secondary)
            TextField("Player \(index + 1)", text: nameBinding(for: index))
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(UIIdentifiers.lobbyPlayerNameField(index: index))
            Toggle("Bot", isOn: botBinding(for: index))
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityIdentifier(UIIdentifiers.lobbyBotToggle(index: index))
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
    }

    private var botSpeedPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bot speed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
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

    #if canImport(GameKit) && canImport(UIKit)
    private var onlineCard: some View {
        card(title: "Online match", icon: "globe") {
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
                        Text(gameCenter.isAuthenticated ? "Find match" : "Sign in to Game Center")
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
        return String(localized: "Sign in to play online")
    }
    #endif

    private func card<Content: View>(title: LocalizedStringKey, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.headline)
            }
            content()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func seatCountButton(count: Int, id: String) -> some View {
        let isSelected = seats.count == count
        if isSelected {
            Button { setSeatCount(count) } label: {
                Text("\(count) players")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.accentColor)
            .accessibilityAddTraits(.isSelected)
            .accessibilityIdentifier(id)
        } else {
            Button { setSeatCount(count) } label: {
                Text("\(count) players")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            .accessibilityIdentifier(id)
        }
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

    private func botBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { seats.indices.contains(index) ? seats[index].kind == .bot : false },
            set: { newValue in
                guard seats.indices.contains(index) else { return }
                seats[index].kind = newValue ? .bot : .human
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

    private func startLocalTable() {
        guard seats.validationError == nil else { return }
        do {
            let lobbyPlayers = seats.map { PlayerID($0.trimmedName) }
            // First dealer = last seat so the first seat ("You") is forehand
            // (first to bid) on deal 1. In 4-player this also keeps the human
            // player active during the very first hand instead of sitting out.
            let defaultDealer = lobbyPlayers.last
            let args = ProcessInfo.processInfo.arguments
            let configuration = TestHarness.resolveConfiguration(
                from: args,
                defaults: TestHarness.Defaults(players: lobbyPlayers, firstDealer: defaultDealer)
            )

            // Viewer policy: pin to the single human if there is exactly one
            // (vs-bots), otherwise follow the active actor (hot-seat). UI
            // tests can force `.followsActor` via the launch flag so the
            // robot can drive each seat's turn from one device.
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
            // UI tests pass `-uiTestDisableAnimations` to skip transitions;
            // honor that for bot pacing too so a full match doesn't burn
            // 500ms × every bot action just waiting.
            if TestHarness.disableAnimations(in: args) {
                model.botMoveDelay = .zero
            } else {
                model.botMoveDelay = botSpeed.delay
            }
            localModel = model
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Default viewer policy when a UI test hasn't forced an override:
    /// pin to the lone human if there is exactly one, otherwise follow
    /// the actor (hot-seat). All-bot tables also follow the actor so the
    /// rendered seat stays current during demos.
    private func defaultViewerPolicy(for players: [PlayerID]) -> ViewerPolicy {
        let humanIndices = seats.indices.filter { seats[$0].kind == .human }
        if humanIndices.count == 1, players.indices.contains(humanIndices[0]) {
            return .pinned(players[humanIndices[0]])
        }
        return .followsActor
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
        case .instant: return .zero
        case .normal:  return .milliseconds(500)
        case .slow:    return .seconds(1)
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
    /// Stock seat names used for fresh rosters.
    static let defaultNames = ["You", "East", "South", "West"]

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
    var validationError: String? {
        let names = map(\.trimmedName)
        if names.contains(where: \.isEmpty) {
            return String(localized: "Every seat needs a name.")
        }
        if Set(names).count != names.count {
            return String(localized: "Names must be unique.")
        }
        if filter({ $0.kind == .human }).isEmpty {
            return String(localized: "At least one seat must be human.")
        }
        return nil
    }
}
