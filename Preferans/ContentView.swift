import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var game: GameViewModel

    var body: some View {
        NavigationStack {
            Group {
                switch game.screen {
                case .lobby:
                    LobbyView()
                case .table:
                    TableView()
                }
            }
            .navigationTitle("Preferans")
        }
    }
}
