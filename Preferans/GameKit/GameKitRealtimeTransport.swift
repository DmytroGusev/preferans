#if canImport(GameKit)
import Foundation
import GameKit

/// Sendable carrier for an incoming GameKit message. We deliberately do
/// NOT hold the underlying `GKPlayer` — `GKPlayer` is non-Sendable, and
/// crossing the GameKit-thread → MainActor hop with a reference would
/// race. The two strings here are everything the room layer needs to
/// reconstruct an `OnlinePeer` (gamePlayerID is the stable identifier;
/// displayName is shown in the UI).
public struct ReceivedGameKitMessage: Sendable {
    public var message: GameWireMessage
    public var senderGamePlayerID: String
    public var senderDisplayName: String
}

@MainActor
public final class GameKitRealtimeTransport: NSObject, ObservableObject, GKMatchDelegate {
    public let match: GKMatch
    @Published public private(set) var connectedPlayerIDs: Set<String>
    @Published public private(set) var lastError: String?

    private var encoder: JSONEncoder { PreferansJSONCoder.encoder }
    private var decoder: JSONDecoder { PreferansJSONCoder.decoder }
    private var continuations: [UUID: AsyncStream<ReceivedGameKitMessage>.Continuation] = [:]

    public init(match: GKMatch) {
        self.match = match
        self.connectedPlayerIDs = Set(match.players.map(\.gamePlayerID))
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
        // Capture sendable identity here on the GameKit callback thread —
        // GKPlayer can't cross the MainActor hop, but its gamePlayerID
        // and displayName are both immutable strings we can carry over.
        let senderID = player.gamePlayerID
        let senderName = player.displayName
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let message = try self.decoder.decode(GameWireMessage.self, from: data)
                for continuation in self.continuations.values {
                    continuation.yield(ReceivedGameKitMessage(
                        message: message,
                        senderGamePlayerID: senderID,
                        senderDisplayName: senderName
                    ))
                }
            } catch {
                self.lastError = "Could not decode GameKit message from \(senderName): \(error.localizedDescription)"
            }
        }
    }

    nonisolated public func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
        let id = player.gamePlayerID
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch state {
            case .connected:
                self.connectedPlayerIDs.insert(id)
            case .disconnected:
                self.connectedPlayerIDs.remove(id)
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
