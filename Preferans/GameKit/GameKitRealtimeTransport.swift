#if canImport(GameKit)
import Foundation
import GameKit

public struct ReceivedGameKitMessage {
    public var message: GameWireMessage
    public var sender: GKPlayer
}

@MainActor
public final class GameKitRealtimeTransport: NSObject, ObservableObject, GKMatchDelegate {
    public let match: GKMatch
    @Published public private(set) var connectedPlayerIDs: Set<String>
    @Published public private(set) var lastError: String?

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var continuations: [UUID: AsyncStream<ReceivedGameKitMessage>.Continuation] = [:]

    public init(match: GKMatch) {
        self.match = match
        self.connectedPlayerIDs = Set(match.players.map(\.gamePlayerID))
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
        super.init()
        self.match.delegate = self
    }

    deinit {
        for continuation in continuations.values {
            continuation.finish()
        }
    }

    public func messages() -> AsyncStream<ReceivedGameKitMessage> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.continuations.removeValue(forKey: id) }
            }
        }
    }

    public func send(_ message: GameWireMessage, to players: [GKPlayer], reliably: Bool = true) throws {
        let data = try encoder.encode(message)
        try match.send(data, to: players, dataMode: reliably ? .reliable : .unreliable)
    }

    public func sendToAll(_ message: GameWireMessage, reliably: Bool = true) throws {
        let data = try encoder.encode(message)
        try match.sendData(toAllPlayers: data, with: reliably ? .reliable : .unreliable)
    }

    public func disconnect() {
        match.disconnect()
    }

    nonisolated public func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let message = try self.decoder.decode(GameWireMessage.self, from: data)
                for continuation in self.continuations.values {
                    continuation.yield(ReceivedGameKitMessage(message: message, sender: player))
                }
            } catch {
                self.lastError = "Could not decode GameKit message from \(player.displayName): \(error.localizedDescription)"
            }
        }
    }

    nonisolated public func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch state {
            case .connected:
                self.connectedPlayerIDs.insert(player.gamePlayerID)
            case .disconnected:
                self.connectedPlayerIDs.remove(player.gamePlayerID)
            case .unknown:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated public func match(_ match: GKMatch, didFailWithError error: Error?) {
        Task { @MainActor [weak self] in
            self?.lastError = error?.localizedDescription
        }
    }
}
#endif
