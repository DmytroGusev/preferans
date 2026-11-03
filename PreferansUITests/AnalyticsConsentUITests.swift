import XCTest
import PreferansEngine

@MainActor
final class AnalyticsConsentUITests: XCTestCase {
    private func launch(live: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [UITestFlags.pinLanguageEn, UITestFlags.disableAnimations,
            "-uiTestAnalyticsConsent", "-settings.analyticsConsent.v1", "unknown",
            "-settings.firstLaunchOnboardingCompleted", "YES"]
        if live { app.launchArguments += ["-analyticsLiveVerification", "-FIRDebugEnabled"] }
        app.launch()
        return app
    }

    func testDeclineDoesNotBlockPlayAndSettingsCanChangeChoice() {
        let app = launch()
        let decline = app.buttons["analytics.decline"]
        XCTAssertTrue(decline.waitForExistence(timeout: 3))
        decline.tap()
        XCTAssertTrue(app.buttons[UIIdentifiers.lobbySettingsButton].waitForExistence(timeout: 2))
        app.buttons[UIIdentifiers.lobbySettingsButton].tap()
        let toggle = app.switches["settings.analytics"]
        reveal(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
    }

    func testLiveFirebaseOptInAndLocalGame() throws {
        guard ProcessInfo.processInfo.environment["PREFERANS_VERIFY_FIREBASE_LIVE"] == "1" else {
            throw XCTSkip("Explicit QA analytics verification only; ordinary UI tests never initialize Firebase.")
        }
        let app = launch(live: true)
        let allow = app.buttons["analytics.allow"]
        XCTAssertTrue(allow.waitForExistence(timeout: 3))
        allow.tap()
        app.buttons[UIIdentifiers.lobbySettingsButton].tap()
        let status = app.staticTexts["settings.analyticsStatus"]
        reveal(status, in: app)
        XCTAssertEqual(status.label, "Analytics is active")
        app.buttons[UIIdentifiers.buttonDismissSheet].tap()
        let start = app.buttons[UIIdentifiers.lobbyStartLocalTable]
        XCTAssertTrue(start.waitForExistence(timeout: 2))
        start.tap()
        let deal = app.buttons[UIIdentifiers.buttonStartDeal]
        if deal.waitForExistence(timeout: 2) { deal.tap() }
        XCTAssertTrue(app.staticTexts[UIIdentifiers.phaseTitle].waitForExistence(timeout: 3))
        print("[firebase-qa] Explicit opt-in initialized the SDK and generated QA-tagged local game events; verify DebugView separately.")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }
}
