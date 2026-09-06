import Foundation
import Combine
import PreferansEngine

/// Shared table presentation surface. Offline simulation and online authority
/// have separate coordinators; neither UI needs to know how moves are executed.
@MainActor
public protocol OnlineGamePresenting: ObservableObject {
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

extension RoomOnlineGameCoordinator: OnlineGamePresenting {
    public var isSubmitting: Bool { false }
}
