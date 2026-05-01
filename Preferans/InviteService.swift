import Foundation

struct InviteLinkParser {
    static func roomCode(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), url.scheme != nil {
            return roomCode(from: url)
        }

        return sanitize(code: trimmed)
    }

    static func roomCode(from url: URL) -> String? {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        if let value = components?.queryItems?.first(where: { $0.name == "code" })?.value,
           let code = sanitize(code: value) {
            return code
        }

        if let host = url.host?.lowercased(),
           host == "join",
           let code = sanitize(code: url.lastPathComponent) {
            return code
        }

        let pathParts = url.pathComponents.filter { $0 != "/" }
        if pathParts.count >= 2,
           pathParts[pathParts.count - 2].lowercased() == "join",
           let code = sanitize(code: pathParts.last ?? "") {
            return code
        }

        return nil
    }

    private static func sanitize(code: String) -> String? {
        let normalized = code
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }

        guard !normalized.isEmpty else { return nil }
        return normalized
    }
}

actor PrototypeRoomService: MultiplayerServicing {
    static let shared = PrototypeRoomService()

    private var roomsByID: [String: OnlineRoom] = [:]
    private var roomIDsByCode: [String: String] = [:]
    private var eventsByRoomID: [String: [MultiplayerGameEvent]] = [:]

    func createRoom(host: OnlineProfile, playerCount: Int, ruleSet: PreferansRuleSet) async throws -> OnlineRoom {
        let code = nextCode()
        let room = OnlineRoom(
            id: code,
            code: code,
            hostPlayerID: host.id,
            playerCount: playerCount,
            ruleSet: ruleSet,
            participants: [
                RoomParticipant(
                    playerID: host.id,
                    displayName: host.displayName,
                    seat: 0,
                    isHost: true
                )
            ]
        )

        roomsByID[room.id] = room
        roomIDsByCode[room.code] = room.id
        return room
    }

    func joinRoom(code: String, player: OnlineProfile) async throws -> OnlineRoom {
        guard let roomID = roomIDsByCode[code], var room = roomsByID[roomID] else {
            throw RoomServiceError.roomNotFound
        }

        if let existingIndex = room.participants.firstIndex(where: { $0.playerID == player.id }) {
            room.participants[existingIndex].displayName = player.displayName
            room.participants[existingIndex].joinedAt = .now
        } else {
            guard !room.isFull else { throw RoomServiceError.roomFull }

            let usedSeats = Set(room.participants.map(\.seat))
            let seat = (0..<room.playerCount).first(where: { !usedSeats.contains($0) }) ?? room.participants.count
            room.participants.append(
                RoomParticipant(
                    playerID: player.id,
                    displayName: player.displayName,
                    seat: seat,
                    isHost: false
                )
            )
        }

        room.updatedAt = .now
        roomsByID[room.id] = room
        return room
    }

    func leaveRoom(roomID: String, playerID: String) async -> OnlineRoom? {
        guard var room = roomsByID[roomID] else { return nil }
        room.participants.removeAll { $0.playerID == playerID }

        if room.participants.isEmpty {
            roomsByID[roomID] = nil
            roomIDsByCode[room.code] = nil
            return nil
        }

        if room.hostPlayerID == playerID, let nextHost = room.sortedParticipants.first {
            room.hostPlayerID = nextHost.playerID
            for index in room.participants.indices {
                room.participants[index].isHost = room.participants[index].playerID == nextHost.playerID
            }
        }

        room.updatedAt = .now
        roomsByID[room.id] = room
        return room
    }

    func updateRoom(roomID: String, hostPlayerID: String, playerCount: Int, ruleSet: PreferansRuleSet) async throws -> OnlineRoom {
        guard var room = roomsByID[roomID] else { throw RoomServiceError.roomNotFound }
        guard room.hostPlayerID == hostPlayerID else { throw RoomServiceError.notHost }
        guard playerCount >= room.participants.count else { throw RoomServiceError.roomFull }

        room.playerCount = playerCount
        room.ruleSet = ruleSet
        room.updatedAt = .now
        roomsByID[room.id] = room
        return room
    }

    func fetchRoom(roomID: String) async throws -> OnlineRoom {
        guard let room = roomsByID[roomID] else { throw RoomServiceError.roomNotFound }
        return room
    }

    func fetchSnapshot(roomID: String) async throws -> MultiplayerGameSnapshot? {
        nil
    }

    func saveSnapshot(_ snapshot: MultiplayerGameSnapshot, for room: OnlineRoom) async throws -> MultiplayerGameSnapshot {
        snapshot
    }

    func fetchEvents(roomID: String, after revision: Int) async throws -> [MultiplayerGameEvent] {
        eventsByRoomID[roomID, default: []]
            .filter { $0.revision > revision }
            .sorted { $0.revision < $1.revision }
    }

    func appendEvent(_ event: MultiplayerGameEvent, expectedRevision: Int, for room: OnlineRoom) async throws -> MultiplayerGameEvent {
        let latestRevision = eventsByRoomID[room.id, default: []].map(\.revision).max() ?? 0
        guard latestRevision == expectedRevision else {
            throw RoomServiceError.revisionConflict(serverRevision: latestRevision)
        }
        eventsByRoomID[room.id, default: []].append(event)
        return event
    }

    nonisolated func roomInvite(for room: OnlineRoom) -> RoomInvite {
        let url = URL(string: "https://preferans.game/join/\(room.code)")!
        return RoomInvite(code: room.code, url: url)
    }

    private func nextCode() -> String {
        while true {
            let code = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).uppercased()
            if roomIDsByCode[code] == nil {
                return code
            }
        }
    }
}
