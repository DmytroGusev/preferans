import Foundation
import PreferansEngine

public struct CloudTableSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID { tableID }
    public var tableID: UUID
    public var status: PreferansGameStatus
    public var hostPlayerID: PlayerID
    public var seats: [PlayerIdentity]
    public var rules: PreferansRules
    public var lastSequence: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var shareURL: URL?

    public init(
        tableID: UUID,
        status: PreferansGameStatus,
        hostPlayerID: PlayerID,
        seats: [PlayerIdentity],
        rules: PreferansRules,
        lastSequence: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        shareURL: URL? = nil
    ) {
        self.tableID = tableID
        self.status = status
        self.hostPlayerID = hostPlayerID
        self.seats = seats
        self.rules = rules
        self.lastSequence = lastSequence
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.shareURL = shareURL
    }
}

public struct CompletedDealArchive: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(tableID.uuidString)-\(sequence)" }
    public var tableID: UUID
    public var sequence: Int
    public var result: DealResult
    public var cumulativeScore: ScoreSheet
    public var completedAt: Date

    public init(tableID: UUID, sequence: Int, result: DealResult, cumulativeScore: ScoreSheet, completedAt: Date = Date()) {
        self.tableID = tableID
        self.sequence = sequence
        self.result = result
        self.cumulativeScore = cumulativeScore
        self.completedAt = completedAt
    }
}
