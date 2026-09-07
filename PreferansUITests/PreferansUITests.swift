import XCTest
import PreferansEngine

/// Lightweight UI smoke coverage for lobby wiring and single-deal transitions.
///
/// Deeper script replay lives in `MatchUITests` / `FullGameUITests`; this file
/// intentionally stays shallow and uses the same identifiers + robot helpers
/// as the rest of the UI suite so screen copy can evolve without breaking
/// tests that only care about behavior.
@MainActor
final class PreferansUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testLobbyRendersCoreControls() {
        let app = launchedApp()
        let robot = MatchUIRobot(app: app)

        robot.waitForElement(UIIdentifiers.lobbyTitle)
        robot.waitForElement(UIIdentifiers.lobbyWatchBots)
        robot.waitForElement(UIIdentifiers.lobbyAddBot)
        robot.waitForElement(UIIdentifiers.lobbyRemoveBot)
        robot.waitForElement(UIIdentifiers.lobbyPlayerNameField(index: 0))
        robot.waitForElement(UIIdentifiers.lobbyStartLocalTable)
        XCTAssertTrue(app.buttons[UIIdentifiers.lobbyStartLocalTable].isHittable)
        XCTAssertFalse(app.buttons[UIIdentifiers.onlineCreateRoom].exists)
        robot.openTableOptions()
        robot.waitForElement(UIIdentifiers.lobbyBotSpeedPicker)
        robot.revealLobbyControl(app.descendants(matching: .any)[UIIdentifiers.lobbyBotSpeedPicker])
        XCTAssertTrue(app.buttons[UIIdentifiers.lobbyStartLocalTable].isHittable)
        MatchScreenshotRecorder(testCase: self, app: app)
            .capture(name: "lobby-table-options-expanded", force: true)
    }

    func testOnboardingRemainsNavigableAtAccessibilityTextSize() {
        let app = XCUIApplication()
        app.launchArguments += [
            UITestFlags.showOnboarding,
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.disableUITestAnimations()
        app.launch()

        let robot = MatchUIRobot(app: app)
        robot.waitForElement(UIIdentifiers.screenOnboarding)

        let recorder = MatchScreenshotRecorder(testCase: self, app: app)
        for index in 0..<4 {
            let continueButton = app.descendants(matching: .any)[UIIdentifiers.onboardingContinue]
            let description = app.staticTexts[UIIdentifiers.onboardingSlideDescription(index)]
            let page = app.scrollViews[UIIdentifiers.onboardingSlide(index)]
            XCTAssertTrue(description.waitForExistence(timeout: 2))
            recorder.capture(name: "onboarding-large-page-\(index + 1)", force: true)
            for _ in 0..<5 where description.frame.maxY > continueButton.frame.minY - 12 {
                page.swipeUp()
            }
            XCTAssertLessThan(description.frame.maxY, continueButton.frame.minY,
                              "The complete explanation must be readable above the action")
            XCTAssertTrue(description.isHittable)
            recorder.capture(name: "onboarding-large-reading-\(index + 1)", force: true)
            XCTAssertTrue(continueButton.isHittable)
            continueButton.tap()
        }
        robot.waitForElement(UIIdentifiers.lobbyTitle)
    }

    func testStartLocalTableThenDeal() {
        let app = launchedApp()
        let robot = MatchUIRobot(app: app)

        robot.startLocalTable()
        robot.waitForPhase("Ready")
        robot.startNextDeal()

        robot.waitForPhase("Bidding")
        robot.waitForElement(UIIdentifiers.Panel.currentTrick.rawValue)
        robot.waitForElement(UIIdentifiers.Panel.bidding.rawValue)
    }

    func testFourPlayerRosterAddsSeat() {
        let app = launchedApp()
        let robot = MatchUIRobot(app: app)

        robot.selectPlayerCount(4)

        robot.waitForElement(UIIdentifiers.lobbyPlayerNameField(index: 3))
    }

    func testBiddingExposesPassAndMisereOptions() {
        let app = launchedApp(extraArguments: [UITestFlags.viewerFollowsActor])
        let robot = MatchUIRobot(app: app)

        robot.startLocalTable()
        robot.startNextDeal()
        robot.waitForPhase("Bidding")

        robot.waitForElement(UIIdentifiers.Panel.bidding.rawValue)
        robot.waitForElement(UIIdentifiers.bidButton(.pass))
        robot.waitForElement(UIIdentifiers.bidButton(.bid(.misere)))
    }

    func testAllPassDrivesEngineIntoPlayingPhase() {
        let app = launchedApp(extraArguments: manualThreePlayerHarness())
        let robot = MatchUIRobot(app: app)

        robot.startLocalTable()
        robot.startNextDeal()
        robot.waitForPhase("Bidding")

        for _ in 0..<3 {
            robot.bid(.pass)
        }

        robot.waitForPhase("Play")
        let passiveStatus = app.descendants(matching: .any)
            .matching(identifier: UIIdentifiers.actionBarPassiveStatus)
            .firstMatch
        if app.windows.firstMatch.frame.width >= 700 {
            XCTAssertTrue(
                passiveStatus.waitForExistence(timeout: 1),
                "iPad should retain the persistent passive play-status lane"
            )
        } else {
            XCTAssertFalse(
                passiveStatus.exists,
                "iPhone should not repeat passive play status below the hand"
            )
        }
    }

    func testSingleTapOffersExplicitPlayConfirmation() throws {
        let app = launchedApp(extraArguments: manualThreePlayerHarness())
        let robot = MatchUIRobot(app: app)

        robot.startLocalTable()
        robot.startNextDeal()
        robot.waitForPhase("Bidding")
        for _ in 0..<3 {
            robot.bid(.pass)
        }
        robot.waitForPhase("Play")

        let selectedIdentifier = try XCTUnwrap(robot.selectFirstPlayableHandCard())
        let selectedCard = app.descendants(matching: .any)
            .matching(identifier: selectedIdentifier)
            .firstMatch
        let play = app.buttons[UIIdentifiers.buttonPlaySelectedCard]

        XCTAssertTrue(
            play.waitForExistence(timeout: 2) && play.isHittable,
            "A single card tap should expose an explicit Play action."
        )
        XCTAssertTrue(selectedCard.exists, "Selecting must not commit an irreversible play.")

        play.tap()

        let cardLeavesHand = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: selectedCard
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [cardLeavesHand], timeout: 2),
            .completed,
            "The explicit Play action should commit the selected card."
        )
    }

    func testFourPlayerRaspasyShowsDealerLeadWithoutRevealingNextTalonCard() {
        let app = launchedApp(
            extraArguments: manualFourPlayerHarness(),
            skipTapToAdvance: false
        )
        let robot = MatchUIRobot(app: app)

        robot.startLocalTable()
        robot.startNextDeal()
        robot.waitForPhase("Bidding")

        for _ in 0..<3 {
            robot.bid(.pass)
        }
        robot.waitForPhase("Play")

        let publicTalonCards = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'card.talon.'")
        )
        XCTAssertEqual(publicTalonCards.count, 1,
                       "only the current raspasy lead should be face-up")

        for _ in 0..<3 {
            XCTAssertTrue(robot.playFirstPlayableHandCard(acceptanceTimeout: 1.5),
                          "each active seat should be able to answer the dealer's talon lead")
        }

        let hold = app.descendants(matching: .any)[UIIdentifiers.tapToAdvance]
        XCTAssertTrue(hold.waitForExistence(timeout: 3),
                      "the completed opening trick should remain visible")
        let trickCards = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'card.trick.'")
        )
        XCTAssertEqual(trickCards.count, 4,
                       "the dealer-owned talon card must join all three responses")
        XCTAssertEqual(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH 'card.trick.north.'")
            ).count,
            1,
            "the sitting-out dealer should own the opening talon card"
        )
        XCTAssertEqual(publicTalonCards.count, 1,
                       "the second talon card must stay hidden during the first-trick hold")
    }

    func testDeterministicScenarioPinsFirstBidder() {
        let app = launchedApp(extraArguments: manualThreePlayerHarness() + [
            UITestFlags.dealScenario, "sortedDeck"
        ])
        let robot = MatchUIRobot(app: app)

        robot.startLocalTable()
        robot.startNextDeal()

        robot.waitForPhase("Bidding")
        XCTAssertEqual(robot.currentViewer(), "north")
        XCTAssertEqual(robot.phaseMessage(), "north to call")
    }

    func testNorthSpadesSixScenarioDrivesEngineToDiscardWindow() {
        let app = launchedApp(extraArguments: manualThreePlayerHarness() + [
            UITestFlags.dealScenario, "northBidsSpadesSix"
        ])
        let robot = MatchUIRobot(app: app)

        robot.startLocalTable()
        robot.startNextDeal()
        robot.waitForPhase("Bidding")

        robot.bid(.bid(.game(GameContract(6, .suit(.spades)))))
        XCTAssertEqual(robot.currentViewer(), "east")
        robot.bid(.pass)
        XCTAssertEqual(robot.currentViewer(), "south")
        robot.bid(.pass)

        robot.waitForPhase("Prikup")
        robot.waitForElement(UIIdentifiers.Panel.discard.rawValue)
        XCTAssertEqual(robot.currentViewer(), "north")
    }

    func testGameScreenShowsCoreSectionsAfterDeal() {
        let app = launchedApp(extraArguments: manualThreePlayerHarness())
        let robot = MatchUIRobot(app: app)

        robot.startLocalTable()
        robot.startNextDeal()
        robot.waitForPhase("Bidding")

        robot.waitForElement(UIIdentifiers.phaseMessage)
        robot.waitForElement(UIIdentifiers.viewerLabel)
        robot.waitForElement(UIIdentifiers.Panel.currentTrick.rawValue)
        robot.waitForElement(UIIdentifiers.Panel.bidding.rawValue)

        let expectedDiameter: CGFloat = app.windows.firstMatch.frame.width >= 700 ? 24 : 20
        for player: PlayerID in ["north", "east", "south"] {
            let badge = app.descendants(matching: .any)[UIIdentifiers.seatOrder(player)]
            XCTAssertTrue(
                badge.waitForExistence(timeout: 1),
                "Every visible seat must retain its stable table-order badge."
            )
            XCTAssertEqual(
                badge.frame.width,
                expectedDiameter,
                accuracy: 1,
                "iPhone and iPad should use deliberately different seat-order density."
            )
        }
    }

    private func launchedApp(
        extraArguments: [String] = [],
        skipTapToAdvance: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += extraArguments
        if skipTapToAdvance {
            app.disableUITestAnimations()
        } else {
            app.pinTestLocaleEnglish()
            app.launchArguments += [
                UITestFlags.disableAnimations,
                UITestFlags.fastBotDelay,
            ]
        }
        app.launch()
        return app
    }

    private func manualThreePlayerHarness() -> [String] {
        [
            UITestFlags.viewerFollowsActor,
            UITestFlags.players, "north,east,south",
            UITestFlags.firstDealer, "south"
        ]
    }

    private func manualFourPlayerHarness() -> [String] {
        [
            UITestFlags.viewerFollowsActor,
            UITestFlags.players, "north,east,south,west",
            UITestFlags.firstDealer, "north",
            UITestFlags.poolTarget, "84"
        ]
    }
}
