import SwiftUI
import PreferansEngine

public struct LocalGameScreen: View {
    @ObservedObject public var model: GameViewModel
    @AppStorage(SettingsKeys.revealAllHands) private var revealAllHands = false

    /// When non-nil, surfaces a "Leave table" affordance in the game header
    /// and a "Back to lobby" CTA on the game-over card so the user always
    /// has a one-tap exit from a local match.
    public var onLeaveTable: (() -> Void)?
    /// When non-nil, the game-over card shows a "Rematch" CTA. Lobby owns
    /// the closure since it has to spin up a new `GameViewModel`.
    public var onRematch: (() -> Void)?

    public init(
        model: GameViewModel,
        onLeaveTable: (() -> Void)? = nil,
        onRematch: (() -> Void)? = nil
    ) {
        self.model = model
        self.onLeaveTable = onLeaveTable
        self.onRematch = onRematch
    }

    public var body: some View {
        let projection = model.projection(revealAll: revealAllHands)
        ProjectionGameScreen(
            projection: projection,
            eventLog: model.eventLog,
            recentEvents: model.recentEvents,
            onSend: model.send,
            onLeaveTable: onLeaveTable,
            onRematch: onRematch
        ) {
            // Hot-seat helper: pick which player's hand the screen shows.
            // Lives inside the game's overflow menu so the top of the screen
            // stays uncluttered.
            Section("View as") {
                ForEach(model.engine.players, id: \.self) { player in
                    Button {
                        model.selectedViewer = player
                    } label: {
                        if player == model.selectedViewer {
                            Label(player.rawValue, systemImage: "checkmark")
                        } else {
                            Text(player.rawValue)
                        }
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if let error = model.displayableError {
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
}
