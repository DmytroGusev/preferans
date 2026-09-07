import XCTest
@testable import PreferansApp
import PreferansEngine

final class TableLayoutModelTests: XCTestCase {
    func testIPadSplitViewKeepsTabletCompositionEvenWithCompactWidth() {
        XCTAssertEqual(
            ProjectionGameLayoutPolicy.resolve(
                isPadDevice: true,
                horizontalSizeClass: .compact,
                verticalSizeClass: .regular
            ),
            .iPad
        )
        XCTAssertEqual(
            ProjectionGameLayoutPolicy.resolve(
                isPadDevice: true,
                horizontalSizeClass: .compact,
                verticalSizeClass: .compact
            ),
            .iPad
        )
    }

    func testIPhoneUsesCompactPortraitAndLandscapeCompositions() {
        XCTAssertEqual(
            ProjectionGameLayoutPolicy.resolve(
                isPadDevice: false,
                horizontalSizeClass: .compact,
                verticalSizeClass: .regular
            ),
            .phonePortrait
        )
        XCTAssertEqual(
            ProjectionGameLayoutPolicy.resolve(
                isPadDevice: false,
                horizontalSizeClass: .compact,
                verticalSizeClass: .compact
            ),
            .phoneLandscape
        )
    }

    func testTrickCardScaleFollowsDeviceWidth() {
        XCTAssertEqual(
            TableCenterLayoutPolicy.trickCardSize(for: .compact),
            .standard
        )
        XCTAssertEqual(
            TableCenterLayoutPolicy.trickCardSize(for: .regular),
            .large
        )
        XCTAssertEqual(
            TableCenterLayoutPolicy.trickCardSize(for: nil),
            .standard
        )
        XCTAssertEqual(
            TableCenterLayoutPolicy.trickCardSize(for: .compact, isPadDevice: true),
            .large
        )
    }

    func testPublicTalonScaleKeepsPhoneCompactAndIPadReadable() {
        XCTAssertEqual(
            TableCenterLayoutPolicy.publicTalonCardSize(for: .compact),
            .compact
        )
        XCTAssertEqual(
            TableCenterLayoutPolicy.publicTalonCardSize(for: .regular),
            .large
        )
        XCTAssertEqual(
            TableCenterLayoutPolicy.publicTalonCardSize(for: nil),
            .compact
        )
        XCTAssertEqual(
            TableCenterLayoutPolicy.publicTalonCardSize(for: .compact, isPadDevice: true),
            .large
        )
    }

    func testTalonExchangeKeepsTabletCardsReadableInCompactSplitView() {
        XCTAssertEqual(
            TableCenterLayoutPolicy.talonCardSize(for: .compact),
            .standard
        )
        XCTAssertEqual(
            TableCenterLayoutPolicy.talonCardSize(for: .compact, isPadDevice: true),
            .large
        )
    }

    func testReadableHandCardsStayTabletSizedInCompactIPadSplitView() {
        XCTAssertEqual(
            TableHandCardSizePolicy.readableSize(
                isPadDevice: true,
                horizontalSizeClass: .compact
            ),
            .large
        )
        XCTAssertEqual(
            TableHandCardSizePolicy.readableSize(
                isPadDevice: false,
                horizontalSizeClass: .compact
            ),
            .standard
        )
        XCTAssertEqual(
            TableHandCardSizePolicy.readableSize(
                isPadDevice: false,
                horizontalSizeClass: .regular
            ),
            .large
        )
    }

    func testGameOverUsesASeparateIPadActionColumnButStacksAccessibilityText() {
        XCTAssertTrue(
            GameOverLayoutPolicy(isRegularWidth: true, usesAccessibilityText: false)
                .usesTwoRegionComposition
        )
        XCTAssertFalse(
            GameOverLayoutPolicy(isRegularWidth: false, usesAccessibilityText: false)
                .usesTwoRegionComposition
        )
        XCTAssertFalse(
            GameOverLayoutPolicy(isRegularWidth: true, usesAccessibilityText: true)
                .usesTwoRegionComposition
        )
    }

    func testDealSummaryUsesSeparateIPadResultAndScoreRegions() {
        XCTAssertTrue(
            DealSummaryLayoutPolicy(isRegularWidth: true, usesAccessibilityText: false)
                .usesTwoRegionComposition
        )
        XCTAssertFalse(
            DealSummaryLayoutPolicy(isRegularWidth: false, usesAccessibilityText: false)
                .usesTwoRegionComposition
        )
        XCTAssertFalse(
            DealSummaryLayoutPolicy(isRegularWidth: true, usesAccessibilityText: true)
                .usesTwoRegionComposition
        )
    }

    func testSeatOrderBadgesScaleForPhoneAndIPadCompositions() {
        XCTAssertEqual(
            SeatOrderBadgeLayoutPolicy(horizontalSizeClass: .compact, isCondensed: false).diameter,
            20
        )
        XCTAssertEqual(
            SeatOrderBadgeLayoutPolicy(horizontalSizeClass: .compact, isCondensed: true).diameter,
            18
        )
        XCTAssertEqual(
            SeatOrderBadgeLayoutPolicy(horizontalSizeClass: .regular, isCondensed: false).diameter,
            24
        )
        XCTAssertEqual(
            SeatOrderBadgeLayoutPolicy(horizontalSizeClass: .regular, isCondensed: true).diameter,
            20
        )
    }

    func testWideRegularChoiceSurfaceUsesFullGrid() {
        let policy = ActionChoiceLayoutPolicy(
            horizontalSizeClass: .regular,
            usesAccessibilityText: false,
            availableWidth: 681
        )

        XCTAssertTrue(policy.usesRegularGrid)
    }

    func testNarrowRegularChoiceSurfaceFallsBackToScrollableRail() {
        let policy = ActionChoiceLayoutPolicy(
            horizontalSizeClass: .regular,
            usesAccessibilityText: false,
            availableWidth: 408
        )

        XCTAssertFalse(policy.usesRegularGrid)
    }

    func testAccessibilityChoiceSurfaceAlwaysUsesScrollableRail() {
        let policy = ActionChoiceLayoutPolicy(
            horizontalSizeClass: .regular,
            usesAccessibilityText: true,
            availableWidth: 1_000
        )

        XCTAssertFalse(policy.usesRegularGrid)
    }

    func testAccessibilityChoiceRailUsesOneNaturalHeightRow() {
        let policy = ActionChoiceLayoutPolicy(
            horizontalSizeClass: .compact,
            verticalSizeClass: .regular,
            usesAccessibilityText: true,
            availableWidth: 390
        )

        XCTAssertFalse(policy.usesTwoRowRail)
    }

    func testStandardPortraitChoiceRailKeepsTwoRows() {
        let policy = ActionChoiceLayoutPolicy(
            horizontalSizeClass: .compact,
            verticalSizeClass: .regular,
            usesAccessibilityText: false,
            availableWidth: 390
        )

        XCTAssertTrue(policy.usesTwoRowRail)
    }

    func testCompactActionBarOmitsPassiveCardPlayStatus() {
        let legal = LegalActionProjection(
            playableCards: [Card(.spades, .ace)]
        )

        XCTAssertFalse(
            ActionBarLayoutPolicy.shouldShow(
                legal: legal,
                horizontalSizeClass: .compact
            )
        )
        XCTAssertTrue(
            ActionBarLayoutPolicy.shouldShow(
                legal: legal,
                horizontalSizeClass: .regular
            )
        )
    }

    func testCompactActionBarAppearsAfterSelectingAPlayableCard() {
        let legal = LegalActionProjection(
            playableCards: [Card(.spades, .ace)]
        )

        XCTAssertTrue(
            ActionBarLayoutPolicy.shouldShow(
                legal: legal,
                hasSelectedPlayCard: true,
                horizontalSizeClass: .compact
            )
        )
    }

    func testCompactActionBarKeepsEveryDedicatedControlSurface() {
        let controlStates = [
            LegalActionProjection(bidCalls: [.pass]),
            LegalActionProjection(whistCalls: [.pass]),
            LegalActionProjection(contractOptions: [GameContract(6, .noTrump)]),
            LegalActionProjection(defenderModes: [.open, .closed]),
            LegalActionProjection(canDiscard: true),
            LegalActionProjection(canAcceptSettlement: true),
            LegalActionProjection(canRejectSettlement: true),
        ]

        for legal in controlStates {
            XCTAssertTrue(
                ActionBarLayoutPolicy.shouldShow(
                    legal: legal,
                    horizontalSizeClass: .compact
                )
            )
        }
    }

    func testRegularSplitKeepsGameplayPrimaryAcrossIPadWidths() {
        let compactPortrait = TableLayoutModel.RegularSplit(totalWidth: 744)
        XCTAssertEqual(compactPortrait.sidebarWidth, 280, accuracy: 0.001)
        XCTAssertEqual(compactPortrait.tableWidth, 432, accuracy: 0.001)

        let largePortrait = TableLayoutModel.RegularSplit(totalWidth: 1_024)
        XCTAssertEqual(largePortrait.sidebarWidth, 286.72, accuracy: 0.001)
        XCTAssertEqual(largePortrait.tableWidth, 705.28, accuracy: 0.001)

        let landscape = TableLayoutModel.RegularSplit(totalWidth: 1_366)
        XCTAssertEqual(landscape.sidebarWidth, 340, accuracy: 0.001)
        XCTAssertEqual(landscape.tableWidth, 994, accuracy: 0.001)
    }

    func testRegularSplitStacksWhenAnIPadWindowCannotFitTheSidebar() {
        XCTAssertFalse(TableLayoutModel.RegularSplit(totalWidth: 899).usesSidebar)
        XCTAssertTrue(TableLayoutModel.RegularSplit(totalWidth: 900).usesSidebar)
    }

    func testRegularSplitClampsInvalidDimensions() {
        let split = TableLayoutModel.RegularSplit(
            totalWidth: -10,
            spacing: -4,
            trailingInset: -8
        )

        XCTAssertEqual(split.totalWidth, 0)
        XCTAssertEqual(split.spacing, 0)
        XCTAssertEqual(split.trailingInset, 0)
        XCTAssertEqual(split.tableWidth, 0)
    }

    func testBannerUsesLowerLaneOnlyWhenCenterFeltIsAvailable() {
        let layout = TableLayoutModel(bounds: CGSize(width: 390, height: 700))

        assertEqual(
            layout.bannerPosition(centerIsAvailable: false),
            CGPoint(x: 195, y: 294)
        )
        assertEqual(
            layout.bannerPosition(centerIsAvailable: true),
            CGPoint(x: 195, y: 364)
        )
    }

    func testClockwiseOpponentsRotateFromEveryViewer() {
        let players: [PlayerID] = ["north", "east", "south", "west"]

        XCTAssertEqual(
            TableLayoutModel.clockwiseOpponents(players: players, viewer: "north"),
            ["east", "south", "west"]
        )
        XCTAssertEqual(
            TableLayoutModel.clockwiseOpponents(players: players, viewer: "east"),
            ["south", "west", "north"]
        )
        XCTAssertEqual(
            TableLayoutModel.clockwiseOpponents(players: players, viewer: "south"),
            ["west", "north", "east"]
        )
        XCTAssertEqual(
            TableLayoutModel.clockwiseOpponents(players: players, viewer: "west"),
            ["north", "east", "south"]
        )
    }

    func testThreePlayerClockwiseOpponentsKeepNextSeatOnTheLeft() {
        let players: [PlayerID] = ["north", "east", "south"]

        XCTAssertEqual(
            TableLayoutModel.clockwiseOpponents(players: players, viewer: "north"),
            ["east", "south"]
        )
        XCTAssertEqual(
            TableLayoutModel.clockwiseOpponents(players: players, viewer: "east"),
            ["south", "north"]
        )
        XCTAssertEqual(
            TableLayoutModel.clockwiseOpponents(players: players, viewer: "south"),
            ["north", "east"]
        )
    }

    func testThreeOpponentSlotsStayInUpperThirdWithCenterSeatHighest() {
        let layout = TableLayoutModel(bounds: CGSize(width: 1_000, height: 700))
        let slots = layout.opponentSlots(opponents: [
            seat("east"),
            seat("south"),
            seat("west")
        ])

        XCTAssertEqual(slots.map(\.orientation), [.left, .top, .right])
        XCTAssertEqual(slots.map(\.kind), [.topNarrow, .topNarrow, .topNarrow])
        XCTAssertEqual(slots.map(\.position.x), [0.18, 0.50, 0.82])
        XCTAssertEqual(slots.map(\.position.y), [0.26, 0.10, 0.26])
        assertEqual(layout.playAreaSize, CGSize(width: 860, height: 434))
        assertEqual(layout.playAreaPosition, CGPoint(x: 500, y: 434))
        assertEqual(layout.slotFrameSize(for: slots[0]), CGSize(width: 190, height: 182))
    }

    func testOpenOpponentEarnsLargerSlotAndShrinksPlayArea() {
        let layout = TableLayoutModel(bounds: CGSize(width: 1_000, height: 700))
        let east = seat("east")
        let openSouth = seat("south", hand: [.known(Card(.spades, .ace)), .hidden])
        let west = seat("west")
        let opponents = [east, openSouth, west]
        let slots = layout.opponentSlots(opponents: opponents)

        // The open seat sits at the top-center; its y nudges down so the
        // taller suit-grouped fan clears the screen edge.
        XCTAssertEqual(slots[1].position.y, 0.22, accuracy: 0.001)
        XCTAssertEqual(slots[0].position.y, 0.26, accuracy: 0.001)
        XCTAssertEqual(slots[2].position.y, 0.26, accuracy: 0.001)

        // Open slot frame grows to fit the bigger two-row face-up hand;
        // hidden peers compact so they do not compete for the same space.
        assertEqual(layout.slotFrameSize(for: slots[1]), CGSize(width: 250, height: 230))
        assertEqual(layout.slotFrameSize(for: slots[0]), CGSize(width: 124, height: 132))

        // Play area shrinks vertically and drifts down to give the open
        // seat headroom above the trick.
        let play = layout.playArea(for: opponents)
        assertEqual(play.size, CGSize(width: 860, height: 350))
        assertEqual(play.position, CGPoint(x: 500, y: 476))
    }

    func testSingleOpenOpponentInTwoSeatLayoutGetsPrimarySpace() {
        let layout = TableLayoutModel(bounds: CGSize(width: 1_000, height: 700))
        let closed = seat("east")
        let open = seat("south", hand: [.known(Card(.spades, .ace)), .known(Card(.hearts, .king))])
        let slots = layout.opponentSlots(opponents: [closed, open])

        XCTAssertEqual(slots.map(\.kind), [.compactHidden, .topNarrow])
        XCTAssertEqual(slots[0].position.x, 0.20, accuracy: 0.001)
        XCTAssertEqual(slots[0].position.y, 0.18, accuracy: 0.001)
        XCTAssertEqual(slots[1].position.x, 0.62, accuracy: 0.001)
        XCTAssertEqual(slots[1].position.y, 0.30, accuracy: 0.001)
        assertEqual(layout.slotFrameSize(for: slots[0]), CGSize(width: 124, height: 132))
        assertEqual(layout.slotFrameSize(for: slots[1]), CGSize(width: 250, height: 230))
    }

    func testTwoOpenOpponentSlotsDoNotOverlapOnCompactWidth() {
        let layout = TableLayoutModel(bounds: CGSize(width: 390, height: 700))
        let first = seat("east", hand: [.known(Card(.spades, .ace)), .known(Card(.hearts, .king))])
        let second = seat("south", hand: [.known(Card(.clubs, .ace)), .known(Card(.diamonds, .king))])
        let slots = layout.opponentSlots(opponents: [first, second])

        let firstSize = layout.slotFrameSize(for: slots[0])
        let secondSize = layout.slotFrameSize(for: slots[1])
        let firstMaxX = slots[0].position.x * layout.bounds.width + firstSize.width / 2
        let secondMinX = slots[1].position.x * layout.bounds.width - secondSize.width / 2

        XCTAssertGreaterThanOrEqual(secondMinX, firstMaxX)
    }

    func testOpponentSlotIdentityFollowsSeatAcrossRotatingDeals() {
        let layout = TableLayoutModel(bounds: CGSize(width: 390, height: 700))
        let firstDeal = layout.opponentSlots(opponents: [seat("east"), seat("south")])
        let nextDeal = layout.opponentSlots(opponents: [seat("south"), seat("west")])

        XCTAssertEqual(firstDeal.map(\.id), ["east", "south"])
        XCTAssertEqual(nextDeal.map(\.id), ["south", "west"])
        XCTAssertNotEqual(
            firstDeal[0].id,
            nextDeal[0].id,
            "a reused visual position must not become a reused SwiftUI identity"
        )
        XCTAssertEqual(firstDeal[1].id, nextDeal[0].id)
    }

    func testTrickOffsetsTrackViewerAndOpponentCount() {
        assertEqual(
            TableLayoutModel.trickOffset(for: "north", viewer: "north", opponents: ["east", "south"]),
            CGSize(width: 0, height: 51.8)
        )
        assertEqual(
            TableLayoutModel.trickOffset(for: "east", viewer: "north", opponents: ["east", "south"]),
            CGSize(width: -57.2, height: -33.3)
        )
        assertEqual(
            TableLayoutModel.trickOffset(for: "south", viewer: "north", opponents: ["east", "south"]),
            CGSize(width: 57.2, height: -33.3)
        )
    }

    private func seat(_ player: PlayerID, hand: [ProjectedCard] = []) -> SeatProjection {
        SeatProjection(
            player: player,
            displayName: player.rawValue,
            isActive: true,
            isDealer: false,
            isCurrentActor: false,
            role: .active,
            hand: hand,
            trickCount: 0
        )
    }

    private func assertEqual(_ actual: CGPoint, _ expected: CGPoint, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.001, file: file, line: line)
    }

    private func assertEqual(_ actual: CGSize, _ expected: CGSize, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.001, file: file, line: line)
    }
}
