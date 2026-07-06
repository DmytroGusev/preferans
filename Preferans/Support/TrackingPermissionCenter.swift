import Foundation
import SwiftUI
#if canImport(AppTrackingTransparency)
import AppTrackingTransparency
#endif
#if canImport(AdSupport)
import AdSupport
#endif

@MainActor
enum TrackingPermissionCenter {
    static var canRequestPermission: Bool {
        #if canImport(AppTrackingTransparency)
        if #available(iOS 14, macCatalyst 14, tvOS 14, *) {
            return ATTrackingManager.trackingAuthorizationStatus == .notDetermined
        }
        #endif
        return false
    }

    static var statusText: String {
        #if canImport(AppTrackingTransparency)
        if #available(iOS 14, macCatalyst 14, tvOS 14, *) {
            switch ATTrackingManager.trackingAuthorizationStatus {
            case .notDetermined: return "Not requested"
            case .restricted: return "Restricted"
            case .denied: return "Denied"
            case .authorized: return "Authorized"
            @unknown default: return "Unknown"
            }
        }
        #endif
        return "Unavailable"
    }

    static func requestPermission() async {
        #if canImport(AppTrackingTransparency)
        if #available(iOS 14, macCatalyst 14, tvOS 14, *) {
            await withCheckedContinuation { continuation in
                ATTrackingManager.requestTrackingAuthorization { _ in
                    continuation.resume()
                }
            }
        }
        #endif
    }

    static var advertisingIdentifierForTracking: UUID? {
        #if canImport(AppTrackingTransparency) && canImport(AdSupport)
        if #available(iOS 14, macCatalyst 14, tvOS 14, *),
           ATTrackingManager.trackingAuthorizationStatus == .authorized {
            return ASIdentifierManager.shared().advertisingIdentifier
        }
        #endif
        return nil
    }
}

struct TrackingConsentPromptModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKeys.trackingPermissionRequested) private var trackingPermissionRequested = false
    @State private var requestStarted = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                scheduleRequestIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                scheduleRequestIfNeeded()
            }
    }

    private func scheduleRequestIfNeeded() {
        guard scenePhase == .active else { return }
        guard !requestStarted else { return }
        guard TrackingPermissionCenter.canRequestPermission else { return }

        requestStarted = true
        Task { @MainActor in
            // Let the first screen settle before iOS presents the system ATT sheet.
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            guard TrackingPermissionCenter.canRequestPermission else { return }
            trackingPermissionRequested = true
            await TrackingPermissionCenter.requestPermission()
        }
    }
}

extension View {
    func requestTrackingConsentOnFirstLaunch() -> some View {
        modifier(TrackingConsentPromptModifier())
    }
}
