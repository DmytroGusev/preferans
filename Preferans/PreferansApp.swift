import SwiftUI

@main
struct PreferansApp: App {
    @StateObject private var game = GameViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(game)
                .onOpenURL { url in
                    game.handleIncomingURL(url)
                }
        }
    }
}
