import SwiftUI
import PreferansEngine

public struct LocalGameScreen: View {
    @ObservedObject public var model: GameViewModel
    @State private var revealAll = true

    public init(model: GameViewModel) {
        self.model = model
    }

    public var body: some View {
        let projection = model.projection(revealAll: revealAll)
        ProjectionGameScreen(projection: projection, eventLog: model.eventLog, onSend: model.send)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Picker("Viewer", selection: $model.selectedViewer) {
                        ForEach(model.engine.players, id: \.self) { player in
                            Text(player.rawValue).tag(player)
                        }
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Toggle("Reveal", isOn: $revealAll)
                }
            }
            .overlay(alignment: .bottom) {
                if let error = model.lastError {
                    Text(error)
                        .font(.caption)
                        .padding()
                        .background(.regularMaterial, in: Capsule())
                        .padding()
                        .accessibilityIdentifier(UIIdentifiers.errorBanner)
                }
            }
    }
}
