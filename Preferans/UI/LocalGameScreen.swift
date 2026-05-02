import SwiftUI
import PreferansEngine

public struct LocalGameScreen: View {
    @ObservedObject public var model: GameViewModel
    @AppStorage(SettingsKeys.revealAllHands) private var revealAllHands = false

    public init(model: GameViewModel) {
        self.model = model
    }

    public var body: some View {
        let projection = model.projection(revealAll: revealAllHands)
        ProjectionGameScreen(projection: projection, eventLog: model.eventLog, onSend: model.send)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
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
                    } label: {
                        Image(systemName: "person.crop.circle.badge")
                            .accessibilityLabel("View as")
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
