import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@main
struct PreferansApp: App {
    #if canImport(GameKit) && canImport(UIKit)
    @StateObject private var gameCenter = GameCenterService()
    @StateObject private var online = HostedOnlineGameCoordinator()
    #endif

    private let animationsDisabled: Bool

    init() {
        // UIKit's flag stops UIView animations; the SwiftUI .transaction
        // modifier below stops implicit/explicit SwiftUI animations the
        // UIKit flag misses. Both are needed to land XCUITest taps on
        // settled frames instead of mid-transition.
        let disabled = TestHarness.disableAnimations(in: ProcessInfo.processInfo.arguments)
        self.animationsDisabled = disabled
        #if canImport(UIKit)
        if disabled {
            UIView.setAnimationsEnabled(false)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            LobbyView()
                .transaction { transaction in
                    if animationsDisabled { transaction.animation = nil }
                }
                #if canImport(GameKit) && canImport(UIKit)
                .environmentObject(gameCenter)
                .environmentObject(online)
                .task { gameCenter.authenticate() }
                #endif
        }
    }
}
