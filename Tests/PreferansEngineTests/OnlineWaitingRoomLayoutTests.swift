import XCTest
@testable import PreferansApp

final class OnlineWaitingRoomLayoutTests: XCTestCase {
    func testDefaultIPadUsesInviteAndRosterRegionsSideBySide() {
        let policy = OnlineWaitingRoomLayoutPolicy(
            isRegularWidth: true,
            usesAccessibilityText: false
        )

        XCTAssertTrue(policy.usesTwoRegionComposition)
    }

    func testAccessibilityTextStacksIPadWaitingRoomRegions() {
        let policy = OnlineWaitingRoomLayoutPolicy(
            isRegularWidth: true,
            usesAccessibilityText: true
        )

        XCTAssertFalse(policy.usesTwoRegionComposition)
    }

    func testIPhoneAlwaysUsesSingleColumnWaitingRoom() {
        for usesAccessibilityText in [false, true] {
            let policy = OnlineWaitingRoomLayoutPolicy(
                isRegularWidth: false,
                usesAccessibilityText: usesAccessibilityText
            )

            XCTAssertFalse(policy.usesTwoRegionComposition)
        }
    }
}
