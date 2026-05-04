import SwiftUI
import PreferansEngine

@MainActor
public final class LobbyViewModel: ObservableObject {
    @Published public var localModel: GameViewModel?
    @Published public var onlineSession: InMemoryOnlineGameSession?
    @Published public var cloudOnlineSession: CloudflareOnlineGameSession?
    @Published public var seats: [LobbySeat] = LobbySeat.defaults(count: 3) {
        didSet { onlineSeatIndex = min(onlineSeatIndex, max(0, seats.count - 1)) }
    }
    @Published public var botSpeed: BotMoveSpeed = .normal
    @Published public var errorText: String?
    @Published public var onlineAccountEmail = "neo@example.test"
    @Published public var onlineSeatIndex = 0
    @Published public var onlineJoinRoomCode = ""
    @Published public var isOnlineRoomLoading = false

    public init() {}

    public func setSeatCount(_ count: Int) {
        seats = LobbySeat.resize(seats, to: count)
    }

    public func setSeatName(_ name: String, at index: Int) {
        guard seats.indices.contains(index) else { return }
        seats[index].name = name
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
        guard seats.validationError == nil, !isOnlineRoomLoading else { return }
        isOnlineRoomLoading = true
        errorText = nil
        let setup = onlineRoomSetup()
        Task { @MainActor [weak self] in
            guard let self else { return }
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

    public func joinCloudflareOnlineRoom() {
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
        Task { @MainActor [weak self] in
            guard let self else { return }
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

    public func startInMemoryOnlineRoom() {
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
            Task { @MainActor [weak self] in
                guard let self else { return }
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

    public func leaveOnlineRoom() {
        onlineSession?.stop()
        onlineSession = nil
        cloudOnlineSession?.stop()
        cloudOnlineSession = nil
    }

    public func handleInviteURL(_ url: URL) {
        guard let roomCode = PreferansInviteLink.roomCode(from: url) else { return }
        onlineJoinRoomCode = roomCode
        errorText = "Invite \(roomCode) is ready. Choose your seat and join the table."
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
                defaults: TestHarness.Defaults(players: lobbyPlayers, firstDealer: defaultDealer)
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
                let strategy = HeuristicStrategy()
                for (index, seat) in configuration.players.enumerated()
                    where seats.indices.contains(index) && seats[index].kind == .bot {
                    model.botStrategies[seat] = strategy
                }
            }

            if TestHarness.fastBotDelay(in: args) {
                model.botMoveDelay = BotPacing.testFast
            } else {
                model.botMoveDelay = (speedOverride ?? botSpeed).delay
            }

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

    /// Default viewer policy when a UI test hasn't forced an override.
    /// Always pinned to the first seat; there is no pass-the-device mode.
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
/// human/bot kind into the same struct as its name so the two can never drift.
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
    /// Stock seat names used for fresh rosters. The "you" pill on the
    /// viewer's seat already marks the human, so seat 0 carries a real name.
    static let defaultNames = ["Neo", "Morpheus", "Trinity", "Agent Smith"]

    static func defaults(count: Int) -> [LobbySeat] {
        precondition(count >= 3 && count <= 4, "Preferans only supports 3- or 4-player tables.")
        return (0..<count).map { index in
            LobbySeat(
                name: defaultNames[index],
                kind: index == 0 ? .human : .bot
            )
        }
    }

    static func quickPlayVsBots() -> [LobbySeat] {
        defaults(count: 3)
    }

    static func demoBots(count: Int) -> [LobbySeat] {
        defaults(count: count).map { seat in
            LobbySeat(id: seat.id, name: seat.name, kind: .bot)
        }
    }

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
