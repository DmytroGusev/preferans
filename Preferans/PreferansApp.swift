import SwiftUI

@main
struct PreferansApp: App {
    #if canImport(GameKit) && canImport(UIKit)
    @StateObject private var gameCenter = GameCenterService()
    @StateObject private var online = HostedOnlineGameCoordinator()
    #endif

    var body: some Scene {
        WindowGroup {
            LobbyView()
                #if canImport(GameKit) && canImport(UIKit)
                .environmentObject(gameCenter)
                .environmentObject(online)
                .task { gameCenter.authenticate() }
                #endif
        }
    }
}
