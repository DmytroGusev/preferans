import SwiftUI
import PreferansEngine
#if canImport(UIKit)
import UIKit
#endif

@main
struct PreferansApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(AppLifecycleDelegate.self) private var appLifecycleDelegate
    #endif

    #if canImport(GameKit) && canImport(UIKit)
    @StateObject private var gameCenter = GameCenterService()
    #endif

    private let animationsDisabled: Bool

    init() {
        // Default to Ukrainian on first launch (overridable in Settings). Has
        // to land before any view loads so `Bundle.main`'s catalog lookup
        // picks the right language for this process. The UI-test flag
        // pins English so XCUI assertions don't drift on simulators
        // whose preferred language differs from the app default.
        let args = ProcessInfo.processInfo.arguments
        if args.contains(UITestFlags.pinLanguageEn) {
            AppLanguage.apply(.en)
        } else {
            AppLanguage.apply(AppLanguage.current)
        }

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

    @ViewBuilder
    private var rootContent: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-previewSettlement") {
            SettlementPreviewGallery()
        } else {
            RootLaunchView()
        }
        #else
        RootLaunchView()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            rootContent
                .environment(\.locale, Locale(identifier: AppLanguage.current.rawValue))
                .transaction { transaction in
                    if animationsDisabled { transaction.animation = nil }
                }
                #if canImport(GameKit) && canImport(UIKit)
                .environmentObject(gameCenter)
                // Game Center authentication is intentionally deferred to
                // an explicit user tap on the lobby's "Sign in to Game
                // Center" button. Auto-authenticating at launch would
                // probe Game Center on every cold start and surface a
                // "local player not authenticated" error before the user
                // had any chance to opt in.
                #endif
        }
    }
}
