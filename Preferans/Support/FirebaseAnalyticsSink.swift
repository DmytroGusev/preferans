#if os(iOS) && canImport(FirebaseCore) && canImport(FirebaseAnalytics)
import FirebaseCore
import FirebaseAnalytics
import Foundation

@MainActor
final class FirebaseAnalyticsSink: AppAnalyticsSink {
    private var configured = false

    func enable() -> Bool {
        if !configured {
            guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
                  let options = FirebaseOptions(contentsOfFile: path),
                  options.bundleID == Bundle.main.bundleIdentifier,
                  options.projectID == "guru-preferans-20261030",
                  options.googleAppID == "1:333127048917:ios:07fabd60aff528315f4c5c" else { return false }
            if FirebaseApp.app() == nil { FirebaseApp.configure(options: options) }
            configured = true
        }
        Analytics.setConsent([.analyticsStorage: .granted, .adStorage: .denied, .adUserData: .denied, .adPersonalization: .denied])
        Analytics.setUserProperty("false", forName: AnalyticsUserPropertyAllowAdPersonalizationSignals)
        #if DEBUG
        Analytics.setDefaultEventParameters(["app_environment": "qa"])
        #else
        Analytics.setDefaultEventParameters(["app_environment": "production"])
        #endif
        Analytics.setAnalyticsCollectionEnabled(true)
        return true
    }

    func disableAndReset() {
        guard configured else { return }
        Analytics.setAnalyticsCollectionEnabled(false)
        Analytics.resetAnalyticsData()
        Analytics.setConsent([.analyticsStorage: .denied, .adStorage: .denied, .adUserData: .denied, .adPersonalization: .denied])
    }

    func log(_ event: AppAnalyticsEvent) {
        Analytics.logEvent(event.name, parameters: event.parameters)
    }
}
#endif
