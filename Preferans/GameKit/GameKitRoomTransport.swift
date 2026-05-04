#if canImport(GameKit)
import Foundation
import GameKit
import PreferansEngine

@MainActor
public final class GameKitRoomTransport: RoomRealtimeTransport {
    public let gameKit: GameKitRealtimeTransport

    public init(match: GKMatch) {
        self.gameKit = GameKitRealtimeTransport(match: match)
    }

    public var localPeer: OnlinePeer {
        peer(for: GKLocalPlayer.local)
    }

    public var participants: [OnlinePeer] {
        orderedPlayers().map(peer(for:))
    }

    public func chooseHost() async -> OnlinePeer? {
        let host = await withCheckedContinuation { continuation in
            gameKit.match.chooseBestHostingPlayer { player in
                continuation.resume(returning: player)
            }
        }
        return host.map(peer(for:))
    }

    public func messages() -> AsyncStream<ReceivedRoomMessage> {
        let gameKitStream = gameKit.messages()
        return AsyncStream { continuation in
            let task = Task { @MainActor [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                for await received in gameKitStream {
                    continuation.yield(
                        ReceivedRoomMessage(
                            message: received.message,
                            sender: self.peer(for: received.sender)
                        )
                    )
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func send(_ message: GameWireMessage, to peers: [OnlinePeer], reliably: Bool) async throws {
        try gameKit.send(message, to: peers.compactMap(player(for:)), reliably: reliably)
    }

    public func sendToAll(_ message: GameWireMessage, reliably: Bool) async throws {
        try gameKit.sendToAll(message, reliably: reliably)
    }

    public func disconnect() {
        gameKit.disconnect()
    }

    private func orderedPlayers() -> [GKPlayer] {
        var unique: [String: GKPlayer] = [GKLocalPlayer.local.gamePlayerID: GKLocalPlayer.local]
        for player in gameKit.match.players {
            unique[player.gamePlayerID] = player
        }
        return unique.values.sorted { $0.gamePlayerID < $1.gamePlayerID }
    }

    private func peer(for player: GKPlayer) -> OnlinePeer {
        OnlinePeer(
            playerID: PlayerID(player.gamePlayerID),
            accountID: player.gamePlayerID,
            provider: .gameCenter,
            displayName: player.displayName
        )
    }

    private func player(for peer: OnlinePeer) -> GKPlayer? {
        if peer.accountID == GKLocalPlayer.local.gamePlayerID || peer.playerID.rawValue == GKLocalPlayer.local.gamePlayerID {
            return GKLocalPlayer.local
        }
        return gameKit.match.players.first {
            $0.gamePlayerID == peer.accountID || $0.gamePlayerID == peer.playerID.rawValue
        }
    }
}
#endif
