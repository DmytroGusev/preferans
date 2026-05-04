import Combine
import Foundation
import PreferansEngine

@MainActor
public final class InMemoryOnlineGameSession: ObservableObject {
    public let room: InMemoryRoom
    public let roomCode: String
    public let localPeer: OnlinePeer
    public let localCoordinator: RoomOnlineGameCoordinator

    private let peers: [OnlinePeer]
    private let hostPlayerID: PlayerID
    private let automatedPlayerIDs: Set<PlayerID>
    private let dealSource: DealSource
    private let botDelay: Duration
    private var transports: [PlayerID: InMemoryRoomTransport] = [:]
    private var remoteCoordinators: [PlayerID: RoomOnlineGameCoordinator] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var pendingBotTasks: [PlayerID: Task<Void, Never>] = [:]

    public init(
        roomCode: String = "LOCAL",
        peers: [OnlinePeer],
        localPlayerID: PlayerID,
        hostPlayerID: PlayerID? = nil,
        automatedPlayerIDs: Set<PlayerID> = [],
        dealSource: DealSource = RandomDealSource(),
        botDelay: Duration = BotPacing.testFast
    ) throws {
        precondition(!peers.isEmpty, "InMemoryOnlineGameSession requires at least one peer.")
        guard let localPeer = peers.first(where: { $0.playerID == localPlayerID }) else {
            throw InMemoryRoom.RoomError.unknownPlayer(localPlayerID)
        }
        self.peers = peers
        self.localPeer = localPeer
        self.hostPlayerID = hostPlayerID ?? peers[0].playerID
        self.automatedPlayerIDs = automatedPlayerIDs
        self.dealSource = dealSource
        self.botDelay = botDelay
        self.room = InMemoryRoom(code: roomCode, peers: peers, hostPlayerID: self.hostPlayerID)
        self.roomCode = roomCode
        self.localCoordinator = RoomOnlineGameCoordinator(dealSource: dealSource)
    }

    deinit {
        for task in pendingBotTasks.values {
            task.cancel()
        }
    }

    public func start(rules: PreferansRules = .sochi) async throws {
        transports = try Dictionary(uniqueKeysWithValues: peers.map { peer in
            (peer.playerID, try room.transport(for: peer.playerID))
        })

        remoteCoordinators = Dictionary(uniqueKeysWithValues: peers
            .filter { $0.playerID != localPeer.playerID }
            .map { ($0.playerID, RoomOnlineGameCoordinator(dealSource: dealSource)) })

        installBotObservers()

        for peer in peers {
            let coordinator = coordinator(for: peer.playerID)
            guard let transport = transports[peer.playerID] else { continue }
            await coordinator.attach(transport: transport, rules: rules)
        }

        for playerID in automatedPlayerIDs {
            scheduleBotIfNeeded(for: playerID)
        }
    }

    public func stop() {
        for task in pendingBotTasks.values {
            task.cancel()
        }
        pendingBotTasks.removeAll()
        cancellables.removeAll()
        localCoordinator.detach()
        for coordinator in remoteCoordinators.values {
            coordinator.detach()
        }
        remoteCoordinators.removeAll()
        transports.removeAll()
    }

    private func coordinator(for playerID: PlayerID) -> RoomOnlineGameCoordinator {
        if playerID == localPeer.playerID {
            return localCoordinator
        }
        if let coordinator = remoteCoordinators[playerID] {
            return coordinator
        }
        let coordinator = RoomOnlineGameCoordinator(dealSource: dealSource)
        remoteCoordinators[playerID] = coordinator
        return coordinator
    }

    private func installBotObservers() {
        cancellables.removeAll()
        for playerID in automatedPlayerIDs {
            coordinator(for: playerID).$projection
                .sink { [weak self] _ in
                    Task { @MainActor in
                        self?.scheduleBotIfNeeded(for: playerID)
                    }
                }
                .store(in: &cancellables)
        }
    }

    private func scheduleBotIfNeeded(for playerID: PlayerID) {
        guard automatedPlayerIDs.contains(playerID),
              let coordinator = remoteCoordinators[playerID],
              let projection = coordinator.projection,
              let action = botAction(from: projection) else {
            return
        }
        pendingBotTasks[playerID]?.cancel()
        let delay = botDelay
        pendingBotTasks[playerID] = Task { [weak coordinator] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                coordinator?.send(action)
            }
        }
    }

    private func botAction(from projection: PlayerGameProjection) -> PreferansAction? {
        let viewer = projection.viewer
        switch projection.phase {
        case .waitingForDeal:
            return nil

        case let .bidding(currentPlayer, _):
            guard currentPlayer == viewer else { return nil }
            if projection.legal.bidCalls.contains(.pass) {
                return .bid(player: viewer, call: .pass)
            }
            guard let fallback = projection.legal.bidCalls.first else { return nil }
            return .bid(player: viewer, call: fallback)

        case let .awaitingDiscard(declarer, _):
            guard declarer == viewer, projection.legal.canDiscard else { return nil }
            let knownCards = projection.talon.compactMap(\.knownCard)
                + (projection.seats.first { $0.player == viewer }?.hand.compactMap(\.knownCard) ?? [])
            guard knownCards.count >= 2 else { return nil }
            return .discard(player: viewer, cards: Array(knownCards.prefix(2)))

        case let .awaitingContract(declarer, _):
            guard declarer == viewer, let contract = projection.legal.contractOptions.first else { return nil }
            return .declareContract(player: viewer, contract: contract)

        case let .awaitingWhist(currentPlayer, _, _):
            guard currentPlayer == viewer else { return nil }
            let call = projection.legal.whistCalls.contains(.pass)
                ? WhistCall.pass
                : projection.legal.whistCalls.first
            guard let call else { return nil }
            return .whist(player: viewer, call: call)

        case let .awaitingDefenderMode(whister, _):
            guard whister == viewer else { return nil }
            let mode = projection.legal.defenderModes.contains(.closed)
                ? DefenderPlayMode.closed
                : projection.legal.defenderModes.first
            guard let mode else { return nil }
            return .chooseDefenderMode(player: viewer, mode: mode)

        case let .playing(currentPlayer, _, _):
            guard currentPlayer == viewer, let card = projection.legal.playableCards.first else { return nil }
            return .playCard(player: viewer, card: card)

        case .dealFinished, .gameOver:
            return nil
        }
    }
}
