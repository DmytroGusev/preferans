import SwiftUI
import PreferansEngine

struct LobbyPublicTablesSection: View {
    @Environment(\.tableTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var viewModel: LobbyViewModel
    @ObservedObject var lobby: PublicTableLobby
    @State private var selectedVariant = ""
    @State private var playerCount = 0
    @State private var poolLength = 0
    @State private var showsPlaying = false
    @State private var selectedTable: PublicOnlineTable?

    private var filtered: [PublicOnlineTable] {
        lobby.tables.filter {
            (selectedVariant.isEmpty || $0.variant == selectedVariant)
                && (playerCount == 0 || $0.maxPlayers == playerCount)
                && (poolLength == 0 || $0.poolTarget == poolLength * $0.maxPlayers)
                && (showsPlaying ? $0.status == .playing : $0.status == .lobby)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Public tables", systemImage: "person.3.sequence.fill")
                    .font(.headline).foregroundStyle(theme.textPrimary)
                Spacer()
                Button { Task { await refresh() } } label: {
                    Image(systemName: "arrow.clockwise").frame(minWidth: 44, minHeight: 44)
                }
                .disabled(lobby.isLoading || viewModel.onlineAccountSessionToken == nil)
                .accessibilityLabel("Refresh tables")
                .accessibilityIdentifier("online.refreshTables")
            }
            ViewThatFits(in: .horizontal) {
                HStack { variantFilter; playerFilter; poolFilter }
                VStack(alignment: .leading) { variantFilter; HStack { playerFilter; poolFilter } }
            }
            Picker("Table status", selection: $showsPlaying) {
                Text("Waiting for players").tag(false)
                Text("In progress").tag(true)
            }
            .modifier(LobbyChoiceControlStyle())

            if viewModel.onlineAccountSessionToken == nil {
                Text("Sign in or continue as a guest to find players.")
                    .font(.subheadline).foregroundStyle(theme.textSecondary)
            } else if let error = lobby.errorText {
                Text(error).font(.footnote).foregroundStyle(theme.error)
                Button("Try again") { Task { await refresh() } }.buttonStyle(.feltSecondary)
            } else if !lobby.hasLoaded && lobby.isLoading {
                ProgressView("Finding tables…").tint(theme.accentStrong)
            } else if filtered.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Group {
                        if showsPlaying { Text("No games in progress") }
                        else { Text("No tables waiting yet") }
                    }
                        .font(.headline).foregroundStyle(theme.textPrimary)
                    Text("Try another filter or open a table for other players to join.")
                        .font(.footnote).foregroundStyle(theme.textSecondary)
                    Button("Create a table") { viewModel.prepareOnlineTableCreation() }
                        .buttonStyle(.feltPrimary)
                }.padding(.vertical, 8)
            } else {
                ForEach(filtered) { table in
                    Button { selectedTable = table } label: { tableRow(table) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("online.publicTable.\(table.roomCode)")
                }
            }
            if lobby.nextOffset != nil {
                Button("Load more tables") {
                    Task { await lobby.refresh(sessionToken: viewModel.onlineAccountSessionToken, loadMore: true) }
                }.disabled(lobby.isLoading)
            }
        }
        .padding(16)
        .background(theme.shade.opacity(0.30), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.accent.opacity(0.22), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("online.publicTables")
        .task(id: viewModel.onlineAccountSessionToken) {
            await refresh()
            guard viewModel.onlineAccountSessionToken != nil else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                if scenePhase == .active && !lobby.isLoading { await refresh() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
        .sheet(item: $selectedTable) { table in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(LobbyFormat.variantDisplayName(table.variant)).font(.largeTitle.bold())
                        tableRow(table)
                        if let variant = PreferansVariant(rawValue: table.variant) {
                            Text(variant.summary).font(.subheadline)
                        }
                        Text("Players").font(.headline)
                        ForEach(Array(table.players.enumerated()), id: \.offset) { _, player in
                            HStack {
                                Text(verbatim: player.displayName)
                                Spacer()
                                if player.ready { Label("Ready", systemImage: "checkmark.circle.fill") }
                                else if !player.connected { Text("Reconnecting…") }
                                else { Text("Not ready") }
                            }.font(.subheadline)
                        }
                        if table.canJoin {
                            Text("Join, check the table settings, and confirm Ready. The host starts when everyone agrees.")
                                .font(.footnote).foregroundStyle(theme.textSecondary)
                            Button("Take a seat") {
                                selectedTable = nil
                                viewModel.joinPublicTable(table)
                            }
                            .buttonStyle(.feltPrimary)
                            .disabled(viewModel.isOnlineRoomLoading)
                            .accessibilityIdentifier("online.takeSeat")
                        } else {
                            Group {
                                if table.status == .playing { Text("This game has started. New players cannot join mid-match.") }
                                else { Text("Every seat is occupied.") }
                            }
                                .font(.footnote).foregroundStyle(theme.textSecondary)
                        }
                    }.padding(20).foregroundStyle(theme.textPrimary)
                }
                .feltBackground()
                .navigationTitle("Table details")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selectedTable = nil } } }
                .themeNavigationChrome()
            }
        }
    }

    private var variantFilter: some View {
        Picker("Convention", selection: $selectedVariant) {
            Text("All conventions").tag("")
            ForEach(PreferansVariant.publicCases) { Text($0.title).tag($0.rawValue) }
        }.pickerStyle(.menu).tint(theme.accentStrong)
    }
    private var playerFilter: some View {
        Picker("Players", selection: $playerCount) {
            Text("3 or 4 players").tag(0)
            Text("3 players").tag(3)
            Text("4 players").tag(4)
        }.pickerStyle(.menu).tint(theme.accentStrong)
    }
    private var poolFilter: some View {
        Picker("Match length", selection: $poolLength) {
            Text("Any length").tag(0)
            Text("Short pulka").tag(11)
            Text("Standard pulka").tag(21)
        }.pickerStyle(.menu).tint(theme.accentStrong)
    }
    private func refresh() async { await lobby.refresh(sessionToken: viewModel.onlineAccountSessionToken) }

    private func tableRow(_ table: PublicOnlineTable) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(LobbyFormat.variantDisplayName(table.variant)).font(.headline)
                Spacer(minLength: 4)
                Text(verbatim: "\(table.players.count)/\(table.maxPlayers)")
                    .font(.headline.monospacedDigit()).foregroundStyle(theme.accentStrong)
            }
            HStack {
                if table.poolClosure == "tableTotal" {
                    Text("Table pool total: \(table.poolTarget)")
                } else {
                    Text("Pulka per player: \(table.settings.displayedPoolTarget(playerCount: table.maxPlayers))")
                }
                Spacer()
                if table.status == .playing { Text("In progress") }
                else if table.openSeats == 0 { Text("Full") }
                else { Text("Open seats: \(table.openSeats)") }
            }.font(.caption).foregroundStyle(theme.textSecondary)
            Text(verbatim: table.players.map(\.displayName).joined(separator: " · "))
                .font(.footnote).foregroundStyle(theme.textSecondary)
                .lineLimit(2)
        }
        .foregroundStyle(theme.textPrimary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.shade.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
    }
}
