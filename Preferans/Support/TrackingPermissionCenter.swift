import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
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

    static func requestPermissionIfNeeded() async {
        guard canRequestPermission else { return }
        UserDefaults.standard.set(true, forKey: SettingsKeys.trackingPermissionRequested)
        await requestPermission()
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

#if canImport(UIKit)
final class AppLifecycleDelegate: NSObject, UIApplicationDelegate {
    private var trackingRequestStarted = false

    func applicationDidBecomeActive(_ application: UIApplication) {
        requestTrackingAuthorizationOnFirstActiveLaunch()
    }

    private func requestTrackingAuthorizationOnFirstActiveLaunch() {
        guard !trackingRequestStarted else { return }
        guard TrackingPermissionCenter.canRequestPermission else { return }

        trackingRequestStarted = true
        Task { @MainActor in
            // ATT must be requested after the app is active and visible.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await TrackingPermissionCenter.requestPermissionIfNeeded()
        }
    }
}
#endif
