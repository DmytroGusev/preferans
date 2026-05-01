#if canImport(CloudKit)
import Foundation
import CloudKit

enum PreferansCKRecordType {
    static let tableSummary = "PreferansTableSummary"
    static let validatedAction = "PreferansValidatedAction"
    static let completedDeal = "PreferansCompletedDeal"
    static let hostSnapshot = "PreferansHostSnapshot"
}

enum PreferansCKField {
    static let tableID = "tableID"
    static let schemaVersion = "schemaVersion"
    static let status = "status"
    static let hostPlayerID = "hostPlayerID"
    static let seatsData = "seatsData"
    static let rulesData = "rulesData"
    static let lastSequence = "lastSequence"
    static let createdAt = "createdAt"
    static let updatedAt = "updatedAt"
    static let actor = "actor"
    static let sequence = "sequence"
    static let actionData = "actionData"
    static let clientNonce = "clientNonce"
    static let baseHostSequence = "baseHostSequence"
    static let eventSummariesData = "eventSummariesData"
    static let parentTable = "parentTable"
    static let snapshotData = "snapshotData"
    static let resultData = "resultData"
    static let scoreData = "scoreData"
    static let completedAt = "completedAt"
    static let publicProjectionData = "publicProjectionData"
}

enum PreferansCKZone {
    static let tables = "PreferansTables"
}

extension CKRecord {
    func setString(_ value: String?, for key: String) {
        if let value { self[key] = value as NSString } else { self[key] = nil }
    }

    func string(for key: String) -> String? {
        self[key] as? String
    }

    func setInt(_ value: Int, for key: String) {
        self[key] = NSNumber(value: value)
    }

    func int(for key: String) -> Int? {
        (self[key] as? NSNumber)?.intValue
    }

    func setDate(_ value: Date?, for key: String) {
        if let value { self[key] = value as NSDate } else { self[key] = nil }
    }

    func date(for key: String) -> Date? {
        self[key] as? Date
    }

    func setData(_ value: Data?, for key: String) {
        if let value { self[key] = value as NSData } else { self[key] = nil }
    }

    func data(for key: String) -> Data? {
        if let data = self[key] as? Data { return data }
        if let data = self[key] as? NSData { return data as Data }
        return nil
    }

    func setEncryptedData(_ value: Data?, for key: String) {
        if let value {
            encryptedValues[key] = value as NSData
        } else {
            encryptedValues[key] = nil
        }
    }

    func encryptedData(for key: String) -> Data? {
        if let data = encryptedValues[key] as? Data { return data }
        if let data = encryptedValues[key] as? NSData { return data as Data }
        return nil
    }
}
#endif
