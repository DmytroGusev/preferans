#if canImport(CloudKit)
import Foundation
import CloudKit
import PreferansEngine

public actor CloudKitGameArchiveStore {
    public enum StoreError: LocalizedError {
        case missingRecordField(String)
        case missingShareURL
        case unexpectedRecordType(String)

        public var errorDescription: String? {
            switch self {
            case let .missingRecordField(field): return "Missing CloudKit field: \(field)"
            case .missingShareURL: return "CloudKit did not return a share URL."
            case let .unexpectedRecordType(type): return "Unexpected CloudKit record type: \(type)"
            }
        }
    }

    private let container: CKContainer
    private let database: CKDatabase
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let zoneID: CKRecordZone.ID
    private var didEnsureZone = false

    public init(containerIdentifier: String = AppIdentifiers.cloudKitContainer) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
        self.zoneID = CKRecordZone.ID(zoneName: PreferansCKZone.tables, ownerName: CKCurrentUserDefaultName)
    }

    public func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }

    public func saveTableSummary(_ summary: CloudTableSummary, latestPublicProjection: PlayerGameProjection?) async throws -> CKRecord.ID {
        try await ensureZone()
        let recordID = tableRecordID(summary.tableID)
        let record = try await fetchOrCreateRecord(recordType: PreferansCKRecordType.tableSummary, recordID: recordID)
        record.setString(summary.tableID.uuidString, for: PreferansCKField.tableID)
        record.setInt(AppIdentifiers.cloudSchemaVersion, for: PreferansCKField.schemaVersion)
        record.setString(summary.status.rawValue, for: PreferansCKField.status)
        record.setString(summary.hostPlayerID.rawValue, for: PreferansCKField.hostPlayerID)
        record.setData(try encoder.encode(summary.seats), for: PreferansCKField.seatsData)
        record.setData(try encoder.encode(summary.rules), for: PreferansCKField.rulesData)
        record.setInt(summary.lastSequence, for: PreferansCKField.lastSequence)
        record.setDate(summary.createdAt, for: PreferansCKField.createdAt)
        record.setDate(Date(), for: PreferansCKField.updatedAt)
        if let latestPublicProjection {
            // The projection is already redacted. Never store raw DealState as the shared/public view.
            record.setData(try encoder.encode(latestPublicProjection), for: PreferansCKField.publicProjectionData)
        }
        let saved = try await database.save(record)
        return saved.recordID
    }

    public func loadTableSummary(tableID: UUID) async throws -> CloudTableSummary {
        try await ensureZone()
        let record = try await database.record(for: tableRecordID(tableID))
        return try decodeTableSummary(record)
    }

    public func appendValidatedAction(_ action: ValidatedActionRecord) async throws {
        try await ensureZone()
        let parentID = tableRecordID(action.tableID)
        let recordName = "action-\(String(format: "%08d", action.sequence))-\(action.clientNonce.uuidString)"
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        let record = CKRecord(recordType: PreferansCKRecordType.validatedAction, recordID: recordID)
        record.setString(action.tableID.uuidString, for: PreferansCKField.tableID)
        record.setInt(AppIdentifiers.cloudSchemaVersion, for: PreferansCKField.schemaVersion)
        record.setInt(action.sequence, for: PreferansCKField.sequence)
        record.setString(action.actor.rawValue, for: PreferansCKField.actor)
        record.setData(try encoder.encode(action.action), for: PreferansCKField.actionData)
        record.setString(action.clientNonce.uuidString, for: PreferansCKField.clientNonce)
        record.setInt(action.baseHostSequence, for: PreferansCKField.baseHostSequence)
        record.setDate(action.createdAt, for: PreferansCKField.createdAt)
        record.setData(try encoder.encode(action.eventSummaries), for: PreferansCKField.eventSummariesData)
        record[PreferansCKField.parentTable] = CKRecord.Reference(recordID: parentID, action: .deleteSelf)
        _ = try await database.save(record)
    }

    public func loadValidatedActions(tableID: UUID) async throws -> [ValidatedActionRecord] {
        try await ensureZone()
        let predicate = NSPredicate(format: "%K == %@", PreferansCKField.tableID, tableID.uuidString)
        let query = CKQuery(recordType: PreferansCKRecordType.validatedAction, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: PreferansCKField.sequence, ascending: true)]
        let records = try await fetchAllRecords(matching: query, in: zoneID)
        return try records.map(decodeValidatedAction)
    }

    public func saveHostSnapshot(_ snapshot: AppEngineSnapshot, tableID: UUID, sequence: Int) async throws {
        try await ensureZone()
        let recordID = CKRecord.ID(recordName: "host-snapshot-\(tableID.uuidString)", zoneID: zoneID)
        let record = try await fetchOrCreateRecord(recordType: PreferansCKRecordType.hostSnapshot, recordID: recordID)
        record.setString(tableID.uuidString, for: PreferansCKField.tableID)
        record.setInt(sequence, for: PreferansCKField.sequence)
        record.setInt(AppIdentifiers.cloudSchemaVersion, for: PreferansCKField.schemaVersion)
        record.setEncryptedData(try encoder.encode(snapshot), for: PreferansCKField.snapshotData)
        _ = try await database.save(record)
    }

    public func loadHostSnapshot(tableID: UUID) async throws -> AppEngineSnapshot {
        try await ensureZone()
        let recordID = CKRecord.ID(recordName: "host-snapshot-\(tableID.uuidString)", zoneID: zoneID)
        let record = try await database.record(for: recordID)
        guard let data = record.encryptedData(for: PreferansCKField.snapshotData) ?? record.data(for: PreferansCKField.snapshotData) else {
            throw StoreError.missingRecordField(PreferansCKField.snapshotData)
        }
        return try decoder.decode(AppEngineSnapshot.self, from: data)
    }

    public func saveCompletedDeal(_ archive: CompletedDealArchive) async throws {
        try await ensureZone()
        let recordName = "deal-\(String(format: "%08d", archive.sequence))-\(archive.tableID.uuidString)"
        let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        let record = CKRecord(recordType: PreferansCKRecordType.completedDeal, recordID: recordID)
        record.setString(archive.tableID.uuidString, for: PreferansCKField.tableID)
        record.setInt(AppIdentifiers.cloudSchemaVersion, for: PreferansCKField.schemaVersion)
        record.setInt(archive.sequence, for: PreferansCKField.sequence)
        record.setData(try encoder.encode(archive.result), for: PreferansCKField.resultData)
        record.setData(try encoder.encode(archive.cumulativeScore), for: PreferansCKField.scoreData)
        record.setDate(archive.completedAt, for: PreferansCKField.completedAt)
        record[PreferansCKField.parentTable] = CKRecord.Reference(recordID: tableRecordID(archive.tableID), action: .none)
        _ = try await database.save(record)
    }

    /// Shares only the redacted table summary root. Host snapshots remain unshared private records.
    public func makeShare(for tableID: UUID, title: String = "Preferans table") async throws -> CKShare {
        try await ensureZone()
        let tableRecord = try await database.record(for: tableRecordID(tableID))
        let share = CKShare(rootRecord: tableRecord)
        share[CKShare.SystemFieldKey.title] = title as NSString
        share.publicPermission = .none

        let result = try await database.modifyRecords(
            saving: [tableRecord, share],
            deleting: [],
            savePolicy: .changedKeys,
            atomically: true
        )
        if let savedShare = result.saveResults[share.recordID], case let .success(record) = savedShare, let share = record as? CKShare {
            return share
        }
        throw StoreError.missingShareURL
    }

    public func installPrivateDatabaseSubscription() async throws {
        let subscriptionID = "preferans-private-db-subscription"
        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await database.save(subscription)
    }

    private func ensureZone() async throws {
        guard !didEnsureZone else { return }
        do {
            _ = try await database.save(CKRecordZone(zoneID: zoneID))
        } catch let error as CKError where error.code == .zoneBusy || error.code == .serverRecordChanged {
            // Benign races when multiple calls create/check the zone.
        } catch let error as CKError where error.code == .unknownItem {
            _ = try await database.save(CKRecordZone(zoneID: zoneID))
        } catch {
            // Saving an existing zone may also return a serverRecordChanged-style error on some OS releases.
            // Surface anything else.
            throw error
        }
        didEnsureZone = true
    }

    private func tableRecordID(_ tableID: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: "table-\(tableID.uuidString)", zoneID: zoneID)
    }

    private func fetchOrCreateRecord(recordType: String, recordID: CKRecord.ID) async throws -> CKRecord {
        do {
            return try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return CKRecord(recordType: recordType, recordID: recordID)
        }
    }

    private func decodeTableSummary(_ record: CKRecord) throws -> CloudTableSummary {
        guard let tableIDText = record.string(for: PreferansCKField.tableID), let tableID = UUID(uuidString: tableIDText) else {
            throw StoreError.missingRecordField(PreferansCKField.tableID)
        }
        guard let statusText = record.string(for: PreferansCKField.status), let status = PreferansGameStatus(rawValue: statusText) else {
            throw StoreError.missingRecordField(PreferansCKField.status)
        }
        guard let hostText = record.string(for: PreferansCKField.hostPlayerID) else {
            throw StoreError.missingRecordField(PreferansCKField.hostPlayerID)
        }
        guard let seatsData = record.data(for: PreferansCKField.seatsData) else {
            throw StoreError.missingRecordField(PreferansCKField.seatsData)
        }
        guard let rulesData = record.data(for: PreferansCKField.rulesData) else {
            throw StoreError.missingRecordField(PreferansCKField.rulesData)
        }
        return CloudTableSummary(
            tableID: tableID,
            status: status,
            hostPlayerID: PlayerID(hostText),
            seats: try decoder.decode([PlayerIdentity].self, from: seatsData),
            rules: try decoder.decode(PreferansRules.self, from: rulesData),
            lastSequence: record.int(for: PreferansCKField.lastSequence) ?? 0,
            createdAt: record.date(for: PreferansCKField.createdAt) ?? Date(),
            updatedAt: record.date(for: PreferansCKField.updatedAt) ?? Date(),
            shareURL: nil
        )
    }

    private func decodeValidatedAction(_ record: CKRecord) throws -> ValidatedActionRecord {
        guard let tableText = record.string(for: PreferansCKField.tableID), let tableID = UUID(uuidString: tableText) else {
            throw StoreError.missingRecordField(PreferansCKField.tableID)
        }
        guard let actorText = record.string(for: PreferansCKField.actor) else {
            throw StoreError.missingRecordField(PreferansCKField.actor)
        }
        guard let actionData = record.data(for: PreferansCKField.actionData) else {
            throw StoreError.missingRecordField(PreferansCKField.actionData)
        }
        guard let nonceText = record.string(for: PreferansCKField.clientNonce), let nonce = UUID(uuidString: nonceText) else {
            throw StoreError.missingRecordField(PreferansCKField.clientNonce)
        }
        let events: [String]
        if let eventData = record.data(for: PreferansCKField.eventSummariesData) {
            events = try decoder.decode([String].self, from: eventData)
        } else {
            events = []
        }
        return ValidatedActionRecord(
            tableID: tableID,
            sequence: record.int(for: PreferansCKField.sequence) ?? 0,
            actor: PlayerID(actorText),
            action: try decoder.decode(WirePreferansAction.self, from: actionData),
            clientNonce: nonce,
            baseHostSequence: record.int(for: PreferansCKField.baseHostSequence) ?? 0,
            createdAt: record.date(for: PreferansCKField.createdAt) ?? Date(),
            eventSummaries: events
        )
    }

    private func fetchAllRecords(matching query: CKQuery, in zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        let first = try await database.records(matching: query, inZoneWith: zoneID)
        records += try first.matchResults.map { try $0.1.get() }
        cursor = first.queryCursor

        while let current = cursor {
            let page = try await database.records(continuingMatchFrom: current)
            records += try page.matchResults.map { try $0.1.get() }
            cursor = page.queryCursor
        }
        return records
    }
}
#endif
