import Foundation
import PreferansEngine

public struct OnlineCommandReceipt: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case accepted, rejected }
    public var tableID: UUID
    public var clientNonce: UUID
    public var sequence: Int
    public var status: Status
    public var code: String?
    public var message: String?
}

/// A local write-ahead record. Submission is disabled if persistence fails.
/// Credentials are never stored here; the command is scoped to account + table.
@MainActor
public final class OnlineCommandOutbox {
    private let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Preferans/Commands", isDirectory: true)
    }

    private func url(table: UUID, account: String) -> URL {
        let accountKey = Data(account.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent("\(table.uuidString)-\(accountKey).json")
    }

    public func load(table: UUID, account: String) throws -> ClientActionEnvelope? {
        let file = url(table: table, account: account)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(ClientActionEnvelope.self, from: Data(contentsOf: file))
    }

    public func store(_ command: ClientActionEnvelope, account: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(command).write(to: url(table: command.tableID, account: account), options: .atomic)
    }

    public func remove(table: UUID, account: String) throws {
        let file = url(table: table, account: account)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}
