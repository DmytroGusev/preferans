import SwiftUI
import PreferansEngine

public struct LocalGameScreen: View {
    @ObservedObject public var model: GameViewModel
    @State private var revealAll = false

    public init(model: GameViewModel) {
        self.model = model
    }

    public var body: some View {
        let projection = model.projection(revealAll: revealAll)
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
                        Section {
                            Toggle("Reveal all hands", isOn: $revealAll)
                        }
                    } label: {
                        Image(systemName: "person.crop.circle.badge")
                            .accessibilityLabel("Local table debug")
                    }
                }
            }
            .overlay(alignment: .top) {
                if let error = model.lastError {
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
