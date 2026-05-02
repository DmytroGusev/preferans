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
    @State private var playerNames = ["You", "East", "South"]
    @State private var botSeats: Set<Int> = [1, 2]
    @State private var errorText: String?
    @State private var showingMatchmaker = false

    private var seatCount: Int { playerNames.count }

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

    private var rosterSummary: String {
        let bots = botSeats.filter { $0 < seatCount }.count
        let humans = seatCount - bots
        let humanLabel = humans == 1 ? "1 human" : "\(humans) humans"
        let botLabel = bots == 1 ? "1 bot" : "\(bots) bots"
        return "\(humanLabel) · \(botLabel)"
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
                .accessibilityIdentifier("button.quickPlayVsBots")

                Text(rosterSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    seatCountButton(count: 3, label: "3 players", id: UIIdentifiers.lobbyPlayerCountThree)
                    seatCountButton(count: 4, label: "4 players", id: UIIdentifiers.lobbyPlayerCountFour)
                }

                VStack(spacing: 8) {
                    ForEach(0..<seatCount, id: \.self) { index in
                        HStack(spacing: 10) {
                            Image(systemName: botSeats.contains(index) ? "cpu" : "person.crop.circle")
                                .foregroundStyle(botSeats.contains(index) ? Color.accentColor : .secondary)
                            TextField("Player \(index + 1)", text: binding(for: index))
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
                .accessibilityIdentifier(UIIdentifiers.lobbyStartLocalTable)
            }
        }
    }

    #if canImport(GameKit) && canImport(UIKit)
    private var onlineCard: some View {
        card(title: "Online match", icon: "globe") {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(gameCenter.isAuthenticated ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(gameCenter.statusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Button {
                    if gameCenter.isAuthenticated {
                        showingMatchmaker = true
                    } else {
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

                if let onlineError = online.errorText {
                    Text(onlineError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }
    #endif

    private func card<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
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
    private func seatCountButton(count: Int, label: String, id: String) -> some View {
        let isSelected = seatCount == count
        if isSelected {
            Button { setSeatCount(count) } label: {
                Text(label)
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
                Text(label)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            .accessibilityIdentifier(id)
        }
    }

    private func binding(for index: Int) -> Binding<String> {
        Binding(
            get: { playerNames.indices.contains(index) ? playerNames[index] : "" },
            set: { newValue in
                guard playerNames.indices.contains(index) else { return }
                playerNames[index] = newValue
            }
        )
    }

    private func botBinding(for index: Int) -> Binding<Bool> {
        Binding(
            get: { botSeats.contains(index) },
            set: { newValue in
                if newValue {
                    botSeats.insert(index)
                } else {
                    botSeats.remove(index)
                }
            }
        )
    }

    private func setSeatCount(_ count: Int) {
        let defaults = ["You", "East", "South", "West"]
        if count > playerNames.count {
            while playerNames.count < count {
                let nextIndex = playerNames.count
                playerNames.append(defaults[nextIndex])
                // New seats default to bots so the human roster doesn't
                // silently grow when the table expands.
                botSeats.insert(nextIndex)
            }
        } else if count < playerNames.count {
            playerNames = Array(playerNames.prefix(count))
            // Drop bot toggles for seats that no longer exist; otherwise
            // they'd silently re-activate next time the user grew the
            // table back to 4 seats.
            botSeats = botSeats.filter { $0 < count }
        }
    }

    private func quickPlayVsBots() {
        playerNames = ["You", "East", "South"]
        botSeats = [1, 2]
        startLocalTable()
    }

    private func startLocalTable() {
        do {
            let lobbyPlayers = playerNames
                .prefix(seatCount)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { PlayerID($0) }
            // First dealer = last seat so the first seat ("You") is forehand
            // (first to bid) on deal 1. In 4-player this also keeps the human
            // player active during the very first hand instead of sitting out.
            let defaultDealer = lobbyPlayers.last
            let args = ProcessInfo.processInfo.arguments
            let configuration = TestHarness.resolveConfiguration(
                from: args,
                defaults: TestHarness.Defaults(players: lobbyPlayers, firstDealer: defaultDealer)
            )
            // Local hot-seat default: viewer follows the active actor so the
            // person holding the device sees their own hand on each turn
            // without diving into the debug picker.
            let model = try GameViewModel(
                players: configuration.players,
                rules: configuration.rules,
                match: configuration.match,
                firstDealer: configuration.firstDealer,
                viewerFollowsActor: true,
                dealSource: configuration.dealSource
            )
            let strategy = HeuristicStrategy()
            for (index, seat) in configuration.players.enumerated() where botSeats.contains(index) {
                model.botStrategies[seat] = strategy
            }
            // UI tests pass `-uiTestDisableAnimations` to skip transitions;
            // honor that for bot pacing too so a full match doesn't burn
            // 500ms × every bot action just waiting.
            if TestHarness.disableAnimations(in: args) {
                model.botMoveDelay = .zero
            }
            // Pin the viewer to the first human seat so the user sees
            // their own hand instead of jumping seats while bots play.
            if let humanIndex = (0..<configuration.players.count).first(where: { !botSeats.contains($0) }) {
                model.selectedViewer = configuration.players[humanIndex]
            }
            localModel = model
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
