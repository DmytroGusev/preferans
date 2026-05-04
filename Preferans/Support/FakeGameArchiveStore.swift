import Foundation
import PreferansEngine

public actor FakeGameArchiveStore: GameArchiveStore {
    public enum StoreError: LocalizedError {
        case missingTable(UUID)
        case missingSnapshot(UUID)

        public var errorDescription: String? {
            switch self {
            case let .missingTable(tableID): return "No archived table summary for \(tableID.uuidString)."
            case let .missingSnapshot(tableID): return "No archived host snapshot for \(tableID.uuidString)."
            }
        }
    }

    private var summaries: [UUID: CloudTableSummary] = [:]
    private var publicProjections: [UUID: PlayerGameProjection] = [:]
    private var actions: [UUID: [ValidatedActionRecord]] = [:]
    private var snapshots: [UUID: HostSnapshotArchive] = [:]
    private var deals: [UUID: [CompletedDealArchive]] = [:]

    public init() {}

    public func upsertTableSummary(_ summary: CloudTableSummary, latestPublicProjection: PlayerGameProjection?) async throws {
        summaries[summary.tableID] = summary
        if let latestPublicProjection {
            publicProjections[summary.tableID] = latestPublicProjection
        }
    }

    public func loadTableSummary(tableID: UUID) async throws -> CloudTableSummary {
        guard let summary = summaries[tableID] else {
            throw StoreError.missingTable(tableID)
        }
        return summary
    }

    public func appendValidatedAction(_ action: ValidatedActionRecord) async throws {
        actions[action.tableID, default: []].append(action)
        actions[action.tableID]?.sort { $0.sequence < $1.sequence }
    }

    public func loadValidatedActions(tableID: UUID) async throws -> [ValidatedActionRecord] {
        actions[tableID] ?? []
    }

    public func saveHostSnapshot(_ snapshot: AppEngineSnapshot, tableID: UUID, sequence: Int) async throws {
        snapshots[tableID] = HostSnapshotArchive(snapshot: snapshot, sequence: sequence)
    }

    public func loadHostSnapshot(tableID: UUID) async throws -> AppEngineSnapshot {
        guard let archive = snapshots[tableID] else {
            throw StoreError.missingSnapshot(tableID)
        }
        return archive.snapshot
    }

    public func saveCompletedDeal(_ archive: CompletedDealArchive) async throws {
        deals[archive.tableID, default: []].append(archive)
        deals[archive.tableID]?.sort { $0.sequence < $1.sequence }
    }

    public func savedSummary(tableID: UUID) -> CloudTableSummary? {
        summaries[tableID]
    }

    public func latestPublicProjection(tableID: UUID) -> PlayerGameProjection? {
        publicProjections[tableID]
    }

    public func savedActions(tableID: UUID) -> [ValidatedActionRecord] {
        actions[tableID] ?? []
    }

    public func savedSnapshot(tableID: UUID) -> HostSnapshotArchive? {
        snapshots[tableID]
    }

    public func savedCompletedDeals(tableID: UUID) -> [CompletedDealArchive] {
        deals[tableID] ?? []
    }
}

public struct HostSnapshotArchive: Sendable, Equatable {
    public var snapshot: AppEngineSnapshot
    public var sequence: Int
}
