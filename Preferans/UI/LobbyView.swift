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
    @State private var playerNames = ["north", "east", "south"]
    @State private var errorText: String?
    @State private var showingMatchmaker = false

    public init() {}

    public var body: some View {
        NavigationView {
            Group {
                if let localModel {
                    LocalGameScreen(model: localModel)
                } else {
                    #if canImport(GameKit) && canImport(UIKit)
                    if let projection = online.projection {
                        ProjectionGameScreen(projection: projection, eventLog: online.eventLog, onSend: online.send)
                            .toolbar {
                                Button("Leave") { online.detach() }
                            }
                    } else {
                        lobbyContent
                    }
                    #else
                    lobbyContent
                    #endif
                }
            }
            .navigationTitle("Preferans")
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
        VStack(spacing: 18) {
            Text("Preferans")
                .font(.largeTitle.bold())
                .accessibilityIdentifier(UIIdentifiers.lobbyTitle)

            VStack(alignment: .leading, spacing: 10) {
                Text("Local table players")
                    .font(.headline)
                ForEach(playerNames.indices, id: \.self) { index in
                    TextField("Player \(index + 1)", text: $playerNames[index])
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier(UIIdentifiers.lobbyPlayerNameField(index: index))
                }
            }

            HStack {
                Button("3 players") {
                    playerNames = Array(playerNames.prefix(3))
                    while playerNames.count < 3 { playerNames.append("player\(playerNames.count + 1)") }
                }
                .accessibilityIdentifier(UIIdentifiers.lobbyPlayerCountThree)
                Button("4 players") {
                    while playerNames.count < 4 { playerNames.append("player\(playerNames.count + 1)") }
                }
                .accessibilityIdentifier(UIIdentifiers.lobbyPlayerCountFour)
            }
            .buttonStyle(.bordered)

            Button("Start Local Table") {
                startLocalTable()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(UIIdentifiers.lobbyStartLocalTable)

            #if canImport(GameKit) && canImport(UIKit)
            Divider()
            Text(gameCenter.statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(gameCenter.isAuthenticated ? "Find Game Center Match" : "Sign in to Game Center") {
                if gameCenter.isAuthenticated {
                    showingMatchmaker = true
                } else {
                    gameCenter.authenticate()
                }
            }
            .buttonStyle(.borderedProminent)

            if let onlineError = online.errorText {
                Text(onlineError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            #endif

            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier(UIIdentifiers.lobbyError)
            }
        }
        .padding()
        .frame(maxWidth: 520)
    }

    private func startLocalTable() {
        do {
            let lobbyPlayers = playerNames
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { PlayerID($0) }
            let args = ProcessInfo.processInfo.arguments
            let configuration = TestHarness.resolveConfiguration(
                from: args,
                defaults: TestHarness.Defaults(players: lobbyPlayers, firstDealer: nil)
            )
            localModel = try GameViewModel(
                players: configuration.players,
                rules: configuration.rules,
                match: configuration.match,
                firstDealer: configuration.firstDealer,
                viewerFollowsActor: configuration.viewerFollowsActor,
                dealSource: configuration.dealSource
            )
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
