import Foundation
import PreferansEngine

/// Authoritative seat-to-peer bookkeeping for one online room.
///
/// Keeping this as a value type makes the waiting-room invariants independent
/// of transport timing: an unclaimed placeholder may be replaced by a human,
/// but a delayed placeholder update may never evict a human or bot that already
/// owns the seat.
struct RoomParticipantRoster {
    private(set) var seats: [PlayerIdentity] = []
    private(set) var peersBySeat: [PlayerID: OnlinePeer] = [:]
    private(set) var botSeats: Set<PlayerID> = []

    init(participants: [OnlinePeer] = []) {
        let ordered = Self.ordered(participants)
        for peer in ordered {
            let existing = peersBySeat[peer.playerID]
            if Self.shouldReplace(existing, with: peer) {
                peersBySeat[peer.playerID] = peer
            }
        }
        seats = peersBySeat.values
            .sorted { $0.playerID.rawValue < $1.playerID.rawValue }
            .map(\.playerIdentity)
        botSeats = Set(peersBySeat.values.filter(\.isBotSeat).map(\.playerID))
    }

    static func ordered(_ participants: [OnlinePeer]) -> [OnlinePeer] {
        participants.sorted {
            if $0.playerID != $1.playerID {
                return $0.playerID.rawValue < $1.playerID.rawValue
            }
            return $0.accountID < $1.accountID
        }
    }

    mutating func reset() {
        self = RoomParticipantRoster()
    }

    mutating func replaceSeats(_ seats: [PlayerIdentity]) {
        self.seats = seats
    }

    func identity(for player: PlayerID) -> PlayerIdentity? {
        seats.first { $0.playerID == player }
    }

    func peer(for player: PlayerID) -> OnlinePeer? {
        peersBySeat[player]
    }

    /// Merge a transport presence snapshot without letting a delayed
    /// `pending:` placeholder overwrite a seat that is already occupied.
    mutating func refresh(with participants: [OnlinePeer]) {
        for peer in participants {
            let existing = peersBySeat[peer.playerID]
            if Self.shouldReplace(existing, with: peer) {
                peersBySeat[peer.playerID] = peer
            }
            if peer.isBotSeat {
                botSeats.insert(peer.playerID)
            }
        }
    }

    /// Adopt a server-authoritative roster. Bot display names are normalized
    /// against seat order so the waiting room and live table use one identity.
    mutating func adopt(_ participants: [OnlinePeer]) {
        for peer in participants {
            let candidate = normalizedBotPeer(peer)
            let existing = peersBySeat[candidate.playerID]
            if Self.shouldReplace(existing, with: candidate) {
                peersBySeat[candidate.playerID] = candidate
                updateSeatIdentity(from: candidate)
            }
            if candidate.isBotSeat {
                botSeats.insert(candidate.playerID)
            }
        }
    }

    mutating func claim(peer: OnlinePeer, as identity: PlayerIdentity) {
        peersBySeat[peer.playerID] = peer
        peersBySeat[identity.playerID] = peer
        if let index = seats.firstIndex(where: { $0.playerID == identity.playerID }) {
            seats[index] = identity
        }
    }

    func acceptsHello(from sender: OnlinePeer, identity: PlayerIdentity) -> Bool {
        guard !sender.isPendingSeat else { return false }
        guard let existing = peersBySeat[identity.playerID] else { return true }
        if existing.isBotSeat { return false }
        if existing.isPendingSeat { return true }
        return existing.accountID == sender.accountID
    }

    @discardableResult
    mutating func fillPendingSeatsWithBots() -> Bool {
        var changed = false
        for index in seats.indices {
            let identity = seats[index]
            guard let peer = peersBySeat[identity.playerID], peer.isPendingSeat else { continue }
            let accountID = "\(OnlinePeer.botAccountPrefix)\(identity.playerID.rawValue)"
            let displayName = botDisplayName(at: index)
            peersBySeat[identity.playerID] = OnlinePeer(
                playerID: identity.playerID,
                accountID: accountID,
                provider: .dev,
                displayName: displayName
            )
            seats[index] = PlayerIdentity(
                playerID: identity.playerID,
                gamePlayerID: accountID,
                displayName: displayName
            )
            botSeats.insert(identity.playerID)
            changed = true
        }
        return changed
    }

    func waitingRoomSeats(localSeat: PlayerID?) -> [WaitingRoomSeat] {
        seats.map { identity in
            let peer = peersBySeat[identity.playerID]
            let occupancy: WaitingRoomSeat.Occupancy
            if identity.playerID == localSeat {
                occupancy = .you(name: identity.displayName)
            } else if let peer, peer.isBotSeat {
                occupancy = .bot(name: peer.displayName)
            } else if peer?.isPendingSeat == true {
                occupancy = .openWaiting
            } else {
                occupancy = .human(name: peer?.displayName ?? identity.displayName)
            }
            return WaitingRoomSeat(player: identity.playerID, occupancy: occupancy)
        }
    }

    var isReadyToStart: Bool {
        !seats.isEmpty && seats.allSatisfy { identity in
            guard let peer = peersBySeat[identity.playerID] else { return false }
            return !peer.isPendingSeat
        }
    }

    private static func shouldReplace(_ existing: OnlinePeer?, with candidate: OnlinePeer) -> Bool {
        guard let existing else { return true }
        if existing.isPendingSeat { return true }
        if candidate.isPendingSeat { return false }
        return true
    }

    private mutating func updateSeatIdentity(from peer: OnlinePeer) {
        guard !peer.isPendingSeat,
              let index = seats.firstIndex(where: { $0.playerID == peer.playerID }) else { return }
        seats[index] = peer.playerIdentity
    }

    private func normalizedBotPeer(_ peer: OnlinePeer) -> OnlinePeer {
        guard peer.isBotSeat,
              let index = seats.firstIndex(where: { $0.playerID == peer.playerID }) else {
            return peer
        }
        let displayName = botDisplayName(at: index)
        guard peer.displayName != displayName else { return peer }
        return OnlinePeer(
            playerID: peer.playerID,
            accountID: peer.accountID,
            provider: peer.provider,
            displayName: displayName
        )
    }

    private func botDisplayName(at seatIndex: Int) -> String {
        "\(String(localized: "Bot")) \(seatIndex + 1)"
    }
}
