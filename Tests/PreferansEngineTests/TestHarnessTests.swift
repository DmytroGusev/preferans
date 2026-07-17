import XCTest
@testable import PreferansApp
import PreferansEngine

final class TestHarnessTests: XCTestCase {
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
}
