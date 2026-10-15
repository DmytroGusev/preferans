import Foundation
import Combine
import PreferansEngine

/// Shared table presentation surface. Offline simulation and online authority
/// have separate coordinators; neither UI needs to know how moves are executed.
@MainActor
public protocol OnlineGamePresenting: ObservableObject {
    var isPublicTable: Bool { get }
    var isReady: Bool { get }
    var isUpdatingReadiness: Bool { get }
    var tableSettings: OnlineTableSettings? { get }
    func setReady(_ ready: Bool) async
    func leaveWaitingTable() async -> Bool
    var projection: PlayerGameProjection? { get }
    var displayProjection: PlayerGameProjection? { get }
    var pendingAdvance: PendingAdvance? { get }
    var eventLog: [String] { get }
    var recentEvents: [PreferansEvent] { get }
    var botInsights: [BotDecisionExplanation] { get }
    var isHost: Bool { get }
    var liveness: OnlineLiveness { get }
    var transportStatus: OnlineTransportStatus { get }
    var errorText: String? { get }
    var rosterSeats: [WaitingRoomSeat] { get }
    var canHostStart: Bool { get }
    var hasDisconnectedHumanSeat: Bool { get }
    var isSubmitting: Bool { get }
    func send(_ action: PreferansAction)
    func startFirstDeal() -> Bool
    func fillOpenSeatsWithBotsAndStart() async
}

public extension OnlineGamePresenting {
    var isPublicTable: Bool { false }
    var isReady: Bool { false }
    var isUpdatingReadiness: Bool { false }
    var tableSettings: OnlineTableSettings? { nil }
    func setReady(_ ready: Bool) async {}
    func leaveWaitingTable() async -> Bool { true }
}

extension RoomOnlineGameCoordinator: OnlineGamePresenting {
    public var isSubmitting: Bool { false }
}
