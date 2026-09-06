import SwiftUI
import PreferansEngine
#if canImport(UIKit)
import UIKit
#endif

public struct OnlineRoomGameScreen<Coordinator: OnlineGamePresenting>: View {
    @ObservedObject public var coordinator: Coordinator
    public var roomCode: String
    public var inviteURL: URL?
    public var onLeaveTable: () -> Void

    public init(
        coordinator: Coordinator,
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
                liveTable(
                    projection: coordinator.displayProjection ?? projection,
                    authoritativeProjection: projection
                )
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
        .overlay(alignment: .top) {
            VStack(spacing: 6) {
                connectionStatusBanner
                if coordinator.isSubmitting {
                    connectionBanner("Sending move…", systemImage: "arrow.up.circle", color: .secondary)
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
            .animation(.default, value: coordinator.transportStatus)
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

    private func liveTable(
        projection: PlayerGameProjection,
        authoritativeProjection: PlayerGameProjection
    ) -> some View {
        ZStack {
            ProjectionGameScreen(
                projection: projection,
                eventLog: coordinator.eventLog,
                recentEvents: coordinator.recentEvents,
                botInsights: coordinator.botInsights,
                pendingAdvance: coordinator.pendingAdvance,
                onSend: coordinator.send,
                onLeaveTable: onLeaveTable,
                extraMenu: {
                    Section("Room") {
                        // A bare Text renders as an inert, mislabeled menu
                        // row — make the code actionable instead.
                        Button {
                            #if canImport(UIKit)
                            UIPasteboard.general.string = roomCode
                            #endif
                        } label: {
                            Label("Copy code \(roomCode)", systemImage: "doc.on.doc")
                        }
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
            onlineFlowState(projection: authoritativeProjection)
        }
        // No screen-level id here: it would propagate onto the inner
        // ProjectionGameScreen and shadow its `screenGame` id. The live table
        // is identified by `screenGame`; the pre-deal state by `screenWaitingRoom`.
    }

    @ViewBuilder
    private var connectionStatusBanner: some View {
        if coordinator.transportStatus == .seatTakenOver {
            connectionBanner(
                "Opened on another device — this table is read-only here.",
                systemImage: "iphone.gen2.radiowaves.left.and.right",
                color: .orange
            )
        } else if coordinator.transportStatus == .reconnecting {
            connectionBanner("Reconnecting…", systemImage: "wifi.exclamationmark", color: .orange)
        } else if !coordinator.isHost, coordinator.liveness == .hostUnreachable {
            connectionBanner("Recovering host…", systemImage: "arrow.triangle.2.circlepath", color: .orange)
        }
    }

    private func connectionBanner(
        _ text: LocalizedStringKey,
        systemImage: String,
        color: Color
    ) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .accessibilityIdentifier(UIIdentifiers.connectionBanner)
            .accessibilityLabel("Connection status")
            .accessibilityValue(Text(text))
    }

    private func onlineFlowState(projection: PlayerGameProjection) -> some View {
        Text("room=\(roomCode) viewer=\(projection.viewer.rawValue) sequence=\(projection.sequence) phase=\(projection.phase.token)")
            .font(.caption2)
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .accessibilityIdentifier(UIIdentifiers.onlineFlowState)
            .accessibilityLabel("Online flow state")
            .accessibilityValue("room \(roomCode), viewer \(projection.viewer.rawValue), sequence \(projection.sequence), phase \(projection.phase.token)")
    }

}
