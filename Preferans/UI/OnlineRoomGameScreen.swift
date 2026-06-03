import SwiftUI
import PreferansEngine

public struct OnlineRoomGameScreen: View {
    @ObservedObject public var coordinator: RoomOnlineGameCoordinator
    public var roomCode: String
    public var inviteURL: URL?
    public var onLeaveTable: () -> Void

    public init(
        coordinator: RoomOnlineGameCoordinator,
        roomCode: String,
        inviteURL: URL? = nil,
        onLeaveTable: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.roomCode = roomCode
        self.inviteURL = inviteURL
        self.onLeaveTable = onLeaveTable
    }

    public var body: some View {
        // No screen-level identifier on this Group: it has a single child, so
        // an identifier here would collapse onto and shadow the child's own id
        // (`screenWaitingRoom` / `screenGame`). Each branch carries its own.
        Group {
            if isLiveTable, let projection = coordinator.projection {
                liveTable(projection: projection)
            } else {
                // Pre-first-deal: the waiting room owns seat occupancy + the
                // prominent invite share, and (for the host) the Start gate.
                OnlineWaitingRoomView(
                    coordinator: coordinator,
                    roomCode: roomCode,
                    inviteURL: inviteURL,
                    onLeaveTable: onLeaveTable
                )
            }
        }
    }

    /// The live table is up once the host has dealt the first hand
    /// (`sequence >= 1`). At sequence 0 we're still in the waiting room; any
    /// non-`waitingForDeal` phase at seq 0 shouldn't happen, but fail toward the
    /// live table rather than trapping the user in the lobby.
    private var isLiveTable: Bool {
        guard let projection = coordinator.projection else { return false }
        if projection.sequence >= 1 { return true }
        if case .waitingForDeal = projection.phase { return false }
        return true
    }

    private func liveTable(projection: PlayerGameProjection) -> some View {
        ZStack {
            ProjectionGameScreen(
                projection: projection,
                eventLog: coordinator.eventLog,
                recentEvents: coordinator.recentEvents,
                onSend: coordinator.send,
                onLeaveTable: onLeaveTable,
                extraMenu: {
                    Section("Room") {
                        Text(roomCode)
                        if let inviteURL {
                            ShareLink(
                                item: inviteURL,
                                subject: Text("Join my Preferans table"),
                                message: Text("Join my Preferans table \(roomCode)")
                            ) {
                                Label("Share invite", systemImage: "square.and.arrow.up")
                            }
                            .accessibilityIdentifier(UIIdentifiers.onlineShareInvite)
                        }
                    }
                }
            )
            onlineFlowState(projection: projection)
        }
        .overlay(alignment: .top) {
            VStack(spacing: 6) {
                if !coordinator.isHost, coordinator.liveness == .hostUnreachable {
                    connectionBanner
                }
                if let error = coordinator.errorText {
                    Text(error)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .accessibilityIdentifier(UIIdentifiers.errorBanner)
                }
            }
            .padding(.top, 8)
            .animation(.default, value: coordinator.liveness)
        }
        // No screen-level id here: it would propagate onto the inner
        // ProjectionGameScreen and shadow its `screenGame` id. The live table
        // is identified by `screenGame`; the pre-deal state by `screenWaitingRoom`.
    }

    private var connectionBanner: some View {
        Label("Host not responding…", systemImage: "wifi.exclamationmark")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .accessibilityIdentifier(UIIdentifiers.connectionBanner)
            .accessibilityLabel("Connection status")
            .accessibilityValue("Host not responding…")
    }

    private func onlineFlowState(projection: PlayerGameProjection) -> some View {
        Text("room=\(roomCode) viewer=\(projection.viewer.rawValue) sequence=\(projection.sequence) phase=\(phaseToken(projection.phase))")
            .font(.caption2)
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityIdentifier(UIIdentifiers.onlineFlowState)
            .accessibilityLabel("Online flow state")
            .accessibilityValue("room \(roomCode), viewer \(projection.viewer.rawValue), sequence \(projection.sequence), phase \(phaseToken(projection.phase))")
    }

    private func phaseToken(_ phase: ProjectedPhase) -> String {
        switch phase {
        case .waitingForDeal:
            return "waitingForDeal"
        case .bidding:
            return "bidding"
        case .awaitingDiscard:
            return "awaitingDiscard"
        case .awaitingContract:
            return "awaitingContract"
        case .awaitingWhist:
            return "awaitingWhist"
        case .awaitingDefenderMode:
            return "awaitingDefenderMode"
        case .playing:
            return "playing"
        case .dealFinished:
            return "dealFinished"
        case .gameOver:
            return "gameOver"
        }
    }
}
