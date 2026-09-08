import XCTest
@testable import PreferansApp
import PreferansEngine

final class TestHarnessTests: XCTestCase {
    func testLocalRoomWorkerRequiresAutomationAndLoopbackRoot() {
        let flag = [UITestFlags.disableAnimations]
        let key = "PREFERANS_ROOM_WORKER_URL"
        XCTAssertNil(TestHarness.localRoomWorkerURL(arguments: [], environment: [key: "http://127.0.0.1:8787"]))
        for raw in ["http://127.0.0.1:8787", "http://localhost:8787/"] {
            XCTAssertEqual(TestHarness.localRoomWorkerURL(arguments: flag, environment: [key: raw])?.absoluteString, raw)
        }
        for raw in ["https://example.com", "http://127.0.0.1.example.com", "http://user:pass@localhost",
                    "http://localhost/remote", "http://localhost?proxy=remote", "http://localhost#fragment"] {
            XCTAssertNil(TestHarness.localRoomWorkerURL(arguments: flag, environment: [key: raw]), raw)
        }
    }

    func testProductionShowsOnlyIncompleteOnboarding() {
        XCTAssertTrue(TestHarness.shouldShowOnboarding(completed: false, arguments: []))
        XCTAssertFalse(TestHarness.shouldShowOnboarding(completed: true, arguments: []))
    }

    func testAutomationBypassesOnboardingRegardlessOfPersistedState() {
        XCTAssertFalse(
            TestHarness.shouldShowOnboarding(
                completed: false,
                arguments: [UITestFlags.disableAnimations]
            )
        )
        XCTAssertFalse(
            TestHarness.shouldShowOnboarding(
                completed: true,
                arguments: [UITestFlags.disableAnimations]
            )
        )
    }

    func testDedicatedAutomationFlagForcesOnboarding() {
        XCTAssertTrue(
            TestHarness.shouldShowOnboarding(
                completed: true,
                arguments: [UITestFlags.showOnboarding]
            )
        )
    }

    func testAutomationLanguagePinsAreExplicitAndDeterministic() {
        XCTAssertEqual(
            TestHarness.pinnedLanguage(in: [UITestFlags.pinLanguageEn]),
            .en
        )
        XCTAssertEqual(
            TestHarness.pinnedLanguage(in: [UITestFlags.pinLanguageRu]),
            .ru
        )
        XCTAssertNil(TestHarness.pinnedLanguage(in: []))
    }
}
