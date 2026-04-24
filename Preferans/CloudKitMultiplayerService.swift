import CloudKit
import Foundation

protocol MultiplayerServicing {
    func createRoom(host: OnlineProfile, playerCount: Int, ruleSet: PreferansRuleSet) async throws -> OnlineRoom
    func joinRoom(code: String, player: OnlineProfile) async throws -> OnlineRoom
    func leaveRoom(roomID: String, playerID: String) async -> OnlineRoom?
    func updateRoom(roomID: String, hostPlayerID: String, playerCount: Int, ruleSet: PreferansRuleSet) async throws -> OnlineRoom
    func fetchRoom(roomID: String) async throws -> OnlineRoom
    func fetchSnapshot(roomID: String) async throws -> MultiplayerGameSnapshot?
    func saveSnapshot(_ snapshot: MultiplayerGameSnapshot, for room: OnlineRoom) async throws -> MultiplayerGameSnapshot
    func fetchEvents(roomID: String, after revision: Int) async throws -> [MultiplayerGameEvent]
    func appendEvent(_ event: MultiplayerGameEvent, expectedRevision: Int, for room: OnlineRoom) async throws -> MultiplayerGameEvent
    func roomInvite(for room: OnlineRoom) -> RoomInvite
}

actor CloudKitMultiplayerService: MultiplayerServicing {
    static let shared = CloudKitMultiplayerService()

    private enum RecordType {
        static let room = "GameRoom"
        static let snapshot = "GameSnapshot"
        static let event = "GameEvent"
    }

    private enum Field {
        static let code = "code"
        static let hostPlayerID = "hostPlayerID"
        static let playerCount = "playerCount"
        static let ruleSet = "ruleSet"
        static let participantsJSON = "participantsJSON"
        static let roomState = "roomState"
        static let updatedAt = "updatedAt"
        static let snapshotJSON = "snapshotJSON"
        static let actionJSON = "actionJSON"
        static let resultingStateJSON = "resultingStateJSON"
        static let revision = "revision"
        static let roomID = "roomID"
        static let updatedByPlayerID = "updatedByPlayerID"
        static let actorPlayerID = "actorPlayerID"
        static let createdAt = "createdAt"
    }

    private let container: CKContainer
    private let database: CKDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(container: CKContainer = CKContainer.default()) {
        self.container = container
        self.database = container.publicCloudDatabase
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func createRoom(host: OnlineProfile, playerCount: Int, ruleSet: PreferansRuleSet) async throws -> OnlineRoom {
        let room = OnlineRoom(
            id: UUID().uuidString,
            code: nextCode(),
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

        try await saveRoomRecord(room)
        return room
    }

    func joinRoom(code: String, player: OnlineProfile) async throws -> OnlineRoom {
        let sanitized = code.uppercased()
        var room = try await fetchRoom(byCode: sanitized)

        if let existing = room.participants.firstIndex(where: { $0.playerID == player.id }) {
            room.participants[existing].displayName = player.displayName
            room.participants[existing].joinedAt = .now
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
        try await saveRoomRecord(room)
        return room
    }

    func leaveRoom(roomID: String, playerID: String) async -> OnlineRoom? {
        do {
            var room = try await fetchRoom(roomID: roomID)
            room.participants.removeAll { $0.playerID == playerID }

            if room.participants.isEmpty {
                try await deleteRecord(recordID: CKRecord.ID(recordName: roomID))
                try? await deleteRecord(recordID: CKRecord.ID(recordName: snapshotRecordName(for: roomID)))
                return nil
            }

            if room.hostPlayerID == playerID, let nextHost = room.sortedParticipants.first {
                room.hostPlayerID = nextHost.playerID
                for index in room.participants.indices {
                    room.participants[index].isHost = room.participants[index].playerID == nextHost.playerID
                }
            }

            room.updatedAt = .now
            try await saveRoomRecord(room)
            return room
        } catch {
            return nil
        }
    }

    func updateRoom(roomID: String, hostPlayerID: String, playerCount: Int, ruleSet: PreferansRuleSet) async throws -> OnlineRoom {
        var room = try await fetchRoom(roomID: roomID)
        guard room.hostPlayerID == hostPlayerID else { throw RoomServiceError.notHost }
        guard playerCount >= room.participants.count else { throw RoomServiceError.roomFull }

        room.playerCount = playerCount
        room.ruleSet = ruleSet
        room.updatedAt = .now
        try await saveRoomRecord(room)
        return room
    }

    func fetchRoom(roomID: String) async throws -> OnlineRoom {
        let record = try await fetchRecord(recordID: CKRecord.ID(recordName: roomID))
        return try decodeRoom(from: record)
    }

    func fetchSnapshot(roomID: String) async throws -> MultiplayerGameSnapshot? {
        do {
            let record = try await fetchRecord(recordID: CKRecord.ID(recordName: snapshotRecordName(for: roomID)))
            return try decodeSnapshot(from: record)
        } catch let error as CKError {
            if error.code == .unknownItem {
                return nil
            }
            throw error
        }
    }

    func saveSnapshot(_ snapshot: MultiplayerGameSnapshot, for room: OnlineRoom) async throws -> MultiplayerGameSnapshot {
        let recordID = CKRecord.ID(recordName: snapshotRecordName(for: room.id))
        let record = try await fetchOrCreateRecord(recordType: RecordType.snapshot, recordID: recordID)
        record[Field.roomID] = room.id as CKRecordValue
        record[Field.revision] = snapshot.revision as CKRecordValue
        record[Field.updatedByPlayerID] = snapshot.updatedByPlayerID as CKRecordValue
        record[Field.updatedAt] = snapshot.updatedAt as CKRecordValue
        record[Field.snapshotJSON] = try encode(snapshot) as CKRecordValue

        let saved = try await save(record: record)
        return try decodeSnapshot(from: saved)
    }

    func fetchEvents(roomID: String, after revision: Int) async throws -> [MultiplayerGameEvent] {
        let predicate = NSPredicate(
            format: "%K == %@ AND %K > %d",
            Field.roomID,
            roomID,
            Field.revision,
            revision
        )
        let query = CKQuery(recordType: RecordType.event, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: Field.revision, ascending: true)]
        return try await perform(query: query).map(decodeEvent)
    }

    func appendEvent(_ event: MultiplayerGameEvent, expectedRevision: Int, for room: OnlineRoom) async throws -> MultiplayerGameEvent {
        let latestRevision = try await latestEventRevision(roomID: room.id)
        guard latestRevision == expectedRevision else {
            throw RoomServiceError.revisionConflict(serverRevision: latestRevision)
        }

        let recordID = CKRecord.ID(recordName: eventRecordName(roomID: room.id, revision: event.revision))
        let record = CKRecord(recordType: RecordType.event, recordID: recordID)
        record[Field.roomID] = event.roomID as CKRecordValue
        record[Field.revision] = event.revision as CKRecordValue
        record[Field.actorPlayerID] = event.actorPlayerID as CKRecordValue
        record[Field.createdAt] = event.createdAt as CKRecordValue
        record[Field.actionJSON] = try encode(event.action) as CKRecordValue
        record[Field.resultingStateJSON] = try encode(event.resultingState) as CKRecordValue

        do {
            let saved = try await save(record: record)
            return try decodeEvent(from: saved)
        } catch {
            throw RoomServiceError.revisionConflict(serverRevision: try await latestEventRevision(roomID: room.id))
        }
    }

    nonisolated func roomInvite(for room: OnlineRoom) -> RoomInvite {
        let url = URL(string: "https://preferans.game/join/\(room.code)")!
        return RoomInvite(code: room.code, url: url)
    }

    private func fetchRoom(byCode code: String) async throws -> OnlineRoom {
        let query = CKQuery(recordType: RecordType.room, predicate: NSPredicate(format: "%K == %@", Field.code, code))
        let records = try await perform(query: query)
        guard let record = records.first else { throw RoomServiceError.roomNotFound }
        return try decodeRoom(from: record)
    }

    private func saveRoomRecord(_ room: OnlineRoom) async throws {
        let record = try await fetchOrCreateRecord(recordType: RecordType.room, recordID: CKRecord.ID(recordName: room.id))
        record[Field.code] = room.code as CKRecordValue
        record[Field.hostPlayerID] = room.hostPlayerID as CKRecordValue
        record[Field.playerCount] = room.playerCount as CKRecordValue
        record[Field.ruleSet] = room.ruleSet.rawValue as CKRecordValue
        record[Field.roomState] = room.state.rawValue as CKRecordValue
        record[Field.updatedAt] = room.updatedAt as CKRecordValue
        record[Field.participantsJSON] = try encode(room.participants) as CKRecordValue
        _ = try await save(record: record)
    }

    private func decodeRoom(from record: CKRecord) throws -> OnlineRoom {
        guard
            let code = record[Field.code] as? String,
            let hostPlayerID = record[Field.hostPlayerID] as? String,
            let playerCount = record[Field.playerCount] as? Int64,
            let ruleSetRaw = record[Field.ruleSet] as? String,
            let ruleSet = PreferansRuleSet(rawValue: ruleSetRaw),
            let participantsJSON = record[Field.participantsJSON] as? String,
            let participants: [RoomParticipant] = try decode(participantsJSON),
            let roomStateRaw = record[Field.roomState] as? String,
            let roomState = OnlineRoomState(rawValue: roomStateRaw)
        else {
            throw RoomServiceError.roomNotFound
        }

        return OnlineRoom(
            id: record.recordID.recordName,
            code: code,
            hostPlayerID: hostPlayerID,
            playerCount: Int(playerCount),
            ruleSet: ruleSet,
            participants: participants,
            state: roomState,
            createdAt: record.creationDate ?? .now,
            updatedAt: record.modificationDate ?? .now
        )
    }

    private func decodeSnapshot(from record: CKRecord) throws -> MultiplayerGameSnapshot {
        guard let json = record[Field.snapshotJSON] as? String else {
            throw RoomServiceError.roomNotFound
        }
        return try decode(json)
    }

    private func decodeEvent(from record: CKRecord) throws -> MultiplayerGameEvent {
        guard
            let roomID = record[Field.roomID] as? String,
            let revision = record[Field.revision] as? Int64,
            let actorPlayerID = record[Field.actorPlayerID] as? String,
            let actionJSON = record[Field.actionJSON] as? String,
            let stateJSON = record[Field.resultingStateJSON] as? String
        else {
            throw RoomServiceError.roomNotFound
        }

        let action: MultiplayerGameAction = try decode(actionJSON)
        let state: MultiplayerGameState = try decode(stateJSON)
        return MultiplayerGameEvent(
            id: record.recordID.recordName,
            roomID: roomID,
            revision: Int(revision),
            actorPlayerID: actorPlayerID,
            createdAt: (record[Field.createdAt] as? Date) ?? record.creationDate ?? .now,
            action: action,
            resultingState: state
        )
    }

    private func latestEventRevision(roomID: String) async throws -> Int {
        let query = CKQuery(recordType: RecordType.event, predicate: NSPredicate(format: "%K == %@", Field.roomID, roomID))
        query.sortDescriptors = [NSSortDescriptor(key: Field.revision, ascending: false)]
        return try await perform(query: query, limit: 1)
            .first
            .flatMap { $0[Field.revision] as? Int64 }
            .map(Int.init) ?? 0
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CKError(.internalError)
        }
        return string
    }

    private func decode<T: Decodable>(_ string: String) throws -> T {
        guard let data = string.data(using: .utf8) else {
            throw CKError(.internalError)
        }
        return try decoder.decode(T.self, from: data)
    }

    private func fetchOrCreateRecord(recordType: String, recordID: CKRecord.ID) async throws -> CKRecord {
        do {
            return try await fetchRecord(recordID: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return CKRecord(recordType: recordType, recordID: recordID)
        }
    }

    private func fetchRecord(recordID: CKRecord.ID) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            database.fetch(withRecordID: recordID) { record, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let record else {
                    continuation.resume(throwing: CKError(.unknownItem))
                    return
                }
                continuation.resume(returning: record)
            }
        }
    }

    private func save(record: CKRecord) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            database.save(record) { saved, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let saved else {
                    continuation.resume(throwing: CKError(.internalError))
                    return
                }
                continuation.resume(returning: saved)
            }
        }
    }

    private func deleteRecord(recordID: CKRecord.ID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            database.delete(withRecordID: recordID) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: ())
            }
        }
    }

    private func perform(query: CKQuery, limit: Int = CKQueryOperation.maximumResults) async throws -> [CKRecord] {
        let response = try await database.records(matching: query, resultsLimit: limit)
        return try response.matchResults.map { _, result in
            try result.get()
        }
    }

    private func nextCode() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).uppercased()
    }

    private func snapshotRecordName(for roomID: String) -> String {
        "snapshot-\(roomID)"
    }

    private func eventRecordName(roomID: String, revision: Int) -> String {
        "\(roomID)-event-\(revision)"
    }
}
