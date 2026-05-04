import Foundation
import PreferansEngine

public protocol GameArchiveStore: Sendable {
    func upsertTableSummary(_ summary: CloudTableSummary, latestPublicProjection: PlayerGameProjection?) async throws
    func loadTableSummary(tableID: UUID) async throws -> CloudTableSummary
    func appendValidatedAction(_ action: ValidatedActionRecord) async throws
    func loadValidatedActions(tableID: UUID) async throws -> [ValidatedActionRecord]
    func saveHostSnapshot(_ snapshot: AppEngineSnapshot, tableID: UUID, sequence: Int) async throws
    func loadHostSnapshot(tableID: UUID) async throws -> AppEngineSnapshot
    func saveCompletedDeal(_ archive: CompletedDealArchive) async throws
}

#if canImport(CloudKit)
extension CloudKitGameArchiveStore: GameArchiveStore {
    public func upsertTableSummary(_ summary: CloudTableSummary, latestPublicProjection: PlayerGameProjection?) async throws {
        _ = try await saveTableSummary(summary, latestPublicProjection: latestPublicProjection)
    }
}
#endif
