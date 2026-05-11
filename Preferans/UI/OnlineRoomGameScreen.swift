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
        Group {
            if let projection = coordinator.projection {
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
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Connecting room \(roomCode)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(TableTheme.inkCream)
                    if let inviteURL {
                        ShareLink(item: inviteURL) {
                            Label("Share invite", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.feltPrimary)
                        .accessibilityIdentifier(UIIdentifiers.onlineShareInvite)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .feltBackground()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.screenOnlineRoom)
        .overlay(alignment: .top) {
            if let error = coordinator.errorText {
                Text(error)
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
                    .accessibilityIdentifier(UIIdentifiers.errorBanner)
            }
        }
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
