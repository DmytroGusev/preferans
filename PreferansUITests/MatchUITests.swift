import XCTest
import PreferansEngine

/// Step-5 smoke test: drives one auction through the `MatchUIRobot` against
/// the Game-1 canonical fixture and asserts the robot's reads match the
/// engine's expected behaviour. Verifies plumbing only — full deal play-out
/// and end-to-end multi-deal driving belong to step 6 (`MatchUIDriver`).
@MainActor
final class MatchUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testDealSummaryBalancesAndNextDeal() {
        checkPassedContractSummary(accessibilityText: false)
    }

    func testDealSummaryBalancesAtLargestTextSize() {
        checkPassedContractSummary(accessibilityText: true)
    }

    func testMatchCompletionRematchAndLeave() {
        checkMatchEnd(accessibilityText: false, tied: false)
    }

    func testMatchCompletionAtLargestTextSize() {
        checkMatchEnd(accessibilityText: true, tied: false)
    }

    func testEqualPoolsFinishWithASharedLead() {
        checkMatchEnd(accessibilityText: false, tied: true)
    }

    func testOpenDefenseSettlementCancelRejectAcceptAndNextDeal() {
        checkSettlementFlow(misere: false, accessibilityText: false)
    }

    func testMisereSettlementCancelRejectAcceptAndNextDeal() {
        checkSettlementFlow(misere: true, accessibilityText: false)
    }

    func testMisereSettlementAtLargestTextSize() {
        checkSettlementFlow(misere: true, accessibilityText: true)
    }

    private func checkSettlementFlow(misere: Bool, accessibilityText: Bool) {
        let app = XCUIApplication()
        app.disableUITestAnimations()
        app.launchArguments += [
            UITestFlags.viewerFollowsActor, UITestFlags.players, "north,east,south",
            UITestFlags.firstDealer, "south", UITestFlags.dealScenario, "sortedDeck",
            UITestFlags.theme, misere ? "midnight" : "parchment",
        ]
        if accessibilityText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        let robot = MatchUIRobot(app: app)
        let recorder = MatchScreenshotRecorder(testCase: self, app: app)
        print("[settlement] auction and exchange")
        robot.startLocalTable()
        robot.startNextDeal()
        let contract = GameContract(6, .suit(.spades))
        robot.bid(.bid(misere ? .misere : .game(contract)))
        robot.bid(.pass)
        robot.bid(.pass)
        robot.takeTalon()
        XCTAssertTrue(robot.discardFirstTwoVisibleCards())
        if !misere {
            robot.declareContract(contract)
            robot.whist(.whist)
            robot.whist(.pass)
            recorder.capture(name: "choose-open-defense", force: true)
            robot.defenderMode(.open)
        }
        robot.waitForPhase("Play")
        for seat in ["east", "south"] {
            let visibleCards = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH %@", "card.hand.\(seat).")
            )
            XCTAssertEqual(visibleCards.count, 10, "Both defender hands must be exposed")
        }
        recorder.capture(name: misere ? "misere-open-hands" : "open-defense-hands", force: true)
        let offer = app.buttons[UIIdentifiers.buttonOfferSettlement]
        XCTAssertTrue(offer.isHittable)
        offer.tap()
        let split = app.descendants(matching: .any)[UIIdentifiers.settlementSplitControl]
        XCTAssertTrue(split.waitForExistence(timeout: 2))
        split.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5)).tap()
        XCTAssertEqual(split.value as? String, "4 of 10")
        recorder.capture(name: "settlement-adjusted", force: true)
        let cancel = app.buttons[UIIdentifiers.buttonCancelSettlement]
        revealSettlementAction(cancel, in: app)
        cancel.tap()
        XCTAssertFalse(split.exists)

        print("[settlement] reject an offer, then agree")
        for rejected in [true, false] {
            offer.tap()
            XCTAssertTrue(split.waitForExistence(timeout: 2))
            XCTAssertEqual(split.value as? String, misere ? "0 of 10" : "6 of 10")
            recorder.capture(name: "settlement-composer", force: true)
            let submit = app.buttons[UIIdentifiers.buttonSubmitSettlement]
            revealSettlementAction(submit, in: app)
            submit.tap()
            let accept = app.buttons[UIIdentifiers.buttonAcceptSettlement]
            let reject = app.buttons[UIIdentifiers.buttonRejectSettlement]
            XCTAssertTrue(accept.waitForExistence(timeout: 2))
            recorder.capture(name: "settlement-response", force: true)
            if rejected {
                app.buttons[UIIdentifiers.buttonDismissSheet].tap()
                let review = app.buttons[UIIdentifiers.buttonReviewSettlement]
                XCTAssertTrue(review.waitForExistence(timeout: 2))
                recorder.capture(name: "settlement-review-cards", force: true)
                review.tap()
                XCTAssertTrue(accept.waitForExistence(timeout: 2))
            }
            revealSettlementAction(rejected ? reject : accept, in: app)
            recorder.capture(name: "settlement-response-actions", force: true)
            XCTAssertTrue(accept.isHittable)
            XCTAssertTrue(reject.isHittable)
            if rejected {
                reject.tap()
                robot.waitForPhase("Play")
                XCTAssertFalse(accept.exists)
            } else {
                accept.tap()
                if misere {
                    let responder = app.staticTexts[UIIdentifiers.settlementResponder]
                    XCTAssertTrue(responder.waitForExistence(timeout: 2))
                    XCTAssertEqual(responder.value as? String, "south")
                    XCTAssertTrue(accept.waitForExistence(timeout: 2))
                    revealSettlementAction(accept, in: app)
                    recorder.capture(name: "settlement-final-response", force: true)
                    accept.tap()
                }
            }
        }
        robot.waitForPhase("Deal complete")
        XCTAssertEqual(app.staticTexts[UIIdentifiers.dealResultStatus].label.lowercased(), "agreed result")
        recorder.capture(name: "settlement-score", force: true)
        let next = app.buttons[UIIdentifiers.buttonStartDeal]
        for _ in 0..<5 where !next.isHittable { app.swipeUp() }
        XCTAssertTrue(next.isHittable)
        recorder.capture(name: "settlement-score-actions", force: true)
        next.tap()
        robot.waitForPhase("Bidding")
    }

    private func revealSettlementAction(_ action: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews[UIIdentifiers.settlementScroll]
        for _ in 0..<4 {
            if action.isHittable && scroll.frame.insetBy(dx: 0, dy: 4).contains(action.frame) { return }
            scroll.swipeUp()
        }
        XCTAssertTrue(action.isHittable && scroll.frame.contains(action.frame),
                      "Settlement action must be fully visible before tapping")
    }

    private func checkMatchEnd(accessibilityText: Bool, tied: Bool) {
        let app = XCUIApplication()
        app.disableUITestAnimations()
        app.launchArguments += [
            UITestFlags.viewerFollowsActor,
            UITestFlags.players, "north,east,south",
            UITestFlags.firstDealer, "south",
            UITestFlags.dealScenario, "sortedDeck",
            UITestFlags.poolTarget, "6",
            UITestFlags.totusPolicy, "asTenTrickGame:true",
            UITestFlags.theme, "nordic",
        ]
        if accessibilityText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        let robot = MatchUIRobot(app: app)
        let recorder = MatchScreenshotRecorder(testCase: self, app: app)
        robot.startLocalTable()
        for deal in 1...(tied ? 3 : 1) {
            print("[match-end] playing deal \(deal)")
            robot.startNextDeal()
            let contract = GameContract(tied ? 6 : 10, .suit(.spades))
            robot.bid(.bid(.game(contract)))
            robot.bid(.pass)
            robot.bid(.pass)
            robot.takeTalon()
            if deal == 1 { recorder.capture(name: "match-prikup-before-discard", force: true) }
            XCTAssertTrue(robot.discardFirstTwoVisibleCards())
            robot.waitForPhase("Contract")
            robot.declareContract(contract)
            robot.whist(.pass)
            robot.whist(.pass)
        }
        robot.waitForPhase("Game over")
        let winner = app.staticTexts[UIIdentifiers.gameOverWinner]
        XCTAssertEqual(winner.label, tied ? "Shared lead: north, east, south" : "north takes the pulka")
        XCTAssertEqual(robot.gameOverDealsPlayed(), tied ? 3 : 1)
        recorder.capture(name: tied ? "match-shared-lead" : "match-winner", force: true)
        let rematch = app.buttons[UIIdentifiers.buttonRematch]
        for _ in 0..<5 where !rematch.isHittable { app.swipeUp() }
        XCTAssertTrue(rematch.isHittable)
        recorder.capture(name: "match-end-actions", force: true)
        rematch.tap()
        robot.waitForPhase("Ready")
        let scores = robot.scoreSnapshot(for: ["north", "east", "south"])
        XCTAssertTrue(scores.values.allSatisfy { $0.pool == 0 && $0.mountain == 0 })
        recorder.capture(name: "rematch-ready", force: true)
        app.buttons[UIIdentifiers.buttonLeaveTable].tap()
        recorder.capture(name: "leave-confirmation", force: true)
        app.buttons["Stay"].tap()
        robot.waitForPhase("Ready")
        app.buttons[UIIdentifiers.buttonLeaveTable].tap()
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@",
                                         "Leave table", UIIdentifiers.buttonLeaveTable)).firstMatch.tap()
        robot.waitForElement(UIIdentifiers.screenLobby)
        XCTAssertTrue(app.buttons[UIIdentifiers.lobbyStartLocalTable].isHittable)
    }

    private func checkPassedContractSummary(accessibilityText: Bool) {
        let app = XCUIApplication()
        app.disableUITestAnimations()
        app.launchArguments += [
            UITestFlags.viewerFollowsActor,
            UITestFlags.players, "north,east,south",
            UITestFlags.firstDealer, "south",
            UITestFlags.dealScenario, "sortedDeck",
            UITestFlags.theme, "clubhouse",
        ]
        if accessibilityText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        let robot = MatchUIRobot(app: app)
        let recorder = MatchScreenshotRecorder(testCase: self, app: app)
        let contract = GameContract(6, .suit(.spades))
        robot.startLocalTable()
        robot.startNextDeal()
        robot.bid(.bid(.game(contract)))
        robot.bid(.pass)
        robot.bid(.pass)
        robot.takeTalon()
        robot.discard([Card(.spades, .king), Card(.spades, .ace)])
        robot.declareContract(contract)
        robot.whist(.pass)
        robot.whist(.pass)
        robot.waitForPhase("Deal complete")

        // A passed six credits 2 pool points (20 whists) to north. The
        // table mean is 20/3, so all three balances must change.
        for (player, expected) in [("north", "+13.3"), ("east", "-6.7"), ("south", "-6.7")] {
            let balance = app.staticTexts[UIIdentifiers.dealBalanceDelta(PlayerID(player))]
            XCTAssertTrue(balance.exists)
            XCTAssertEqual(balance.label, "Balance")
            XCTAssertEqual(balance.value as? String, expected)
            if accessibilityText {
                XCTAssertGreaterThan(balance.frame.height, 30, "Result text must honor accessibility sizes")
            }
        }
        recorder.capture(name: accessibilityText ? "score-largest-text" : "score-fractional-balances", force: true)
        let nextDeal = app.buttons[UIIdentifiers.buttonStartDeal]
        for _ in 0..<4 where !nextDeal.isHittable { app.swipeUp() }
        XCTAssertTrue(nextDeal.isHittable, "Next deal must remain reachable after reading the result")
        if accessibilityText {
            recorder.capture(name: "score-largest-text-actions", force: true)
        }
        nextDeal.tap()
        robot.waitForPhase("Bidding")
        XCTAssertEqual(robot.scoreSnapshot(for: ["north"])["north"]?.pool, 2)
        recorder.capture(name: accessibilityText ? "next-deal-largest-text" : "next-deal", force: true)
    }

    /// Launches with Game 1 (`firstDealer = north`, 4 players, classic Sochi,
    /// `asTenTrickGame(requireWhist: false)`, `poolTarget = 20`). Drives the
    /// first deal's auction (east opens 6♠, south and west pass) and asserts
    /// the engine transitions through `Bidding → Prikup` while the
    /// robot's readings stay coherent with the engine's state.
    func testRobotDrivesGame1FirstAuctionToTalonExchange() {
        let app = XCUIApplication()
        app.configureForMatchScript("game1")
        app.launch()

        let robot = MatchUIRobot(app: app)

        // Lobby — start the local table with the script's pre-resolved roster.
        robot.startLocalTable()

        // Match begins in waitingForDeal — user (or test) clicks Deal
        // to consume the first scripted deck.
        robot.waitForPhase("Ready")
        robot.startNextDeal()

        // Bidding opens with east as the active rotation's first bidder.
        robot.waitForPhase("Bidding")
        XCTAssertEqual(robot.currentViewer(), "east",
                       "viewerFollowsActor should pin the viewer to the first bidder.")

        // Score sheet is empty before any deal scores.
        let initialScores = robot.scoreSnapshot(for: MatchScriptFixtures.players)
        for player in MatchScriptFixtures.players {
            XCTAssertEqual(initialScores[player]?.pool, 0, "Pool for \(player) must start at 0.")
            XCTAssertEqual(initialScores[player]?.mountain, 0, "Mountain for \(player) must start at 0.")
        }

        // East opens 6♠.
        let sixSpades = BidCall.bid(.game(GameContract(6, .suit(.spades))))
        robot.bid(sixSpades)
        robot.waitForPhase("Bidding") // still bidding — south's turn now

        XCTAssertEqual(robot.currentViewer(), "south",
                       "viewer should rotate to south after east's bid.")

        // South passes — viewer rotates to west.
        robot.bid(.pass)
        robot.waitForPhase("Bidding")
        XCTAssertEqual(robot.currentViewer(), "west")

        // West passes — auction ends, prikup exchange opens with east declaring.
        robot.bid(.pass)
        robot.waitForPhase("Prikup")
        XCTAssertEqual(robot.currentViewer(), "east",
                       "viewer should follow the declarer into the discard window.")

        // No score has accrued yet — the deal is mid-flight.
        XCTAssertEqual(robot.scoreSnapshot(for: ["east"])["east"]?.pool, 0)
        XCTAssertNil(robot.errorBanner(), "Engine should not have surfaced any errors during the auction.")
    }

    /// The optional ten-trick whist convention enters the ordinary defense
    /// decision flow. It must not turn the deal into a forced-whist variant:
    /// both defenders may independently pass, and half-whist is unavailable
    /// above level seven.
    func testTenTrickConventionOffersBothDefendersPassOrWhist() {
        let app = XCUIApplication()
        app.launchArguments += [
            UITestFlags.viewerFollowsActor,
            UITestFlags.players, "north,east,south",
            UITestFlags.firstDealer, "south",
            UITestFlags.dealScenario, "sortedDeck",
            UITestFlags.totusPolicy, "asTenTrickGame:true",
        ]
        app.disableUITestAnimations()
        app.launch()

        let robot = MatchUIRobot(app: app)
        let contract = GameContract(10, .suit(.spades))

        robot.startLocalTable()
        robot.startNextDeal()
        robot.waitForPhase("Bidding")

        robot.bid(.bid(.game(contract)))
        robot.bid(.pass)
        robot.bid(.pass)

        robot.waitForPhase("Prikup")
        robot.takeTalon()
        robot.discard([
            Card(.spades, .king),
            Card(.spades, .ace),
        ])
        robot.waitForPhase("Contract")
        robot.declareContract(contract)

        robot.waitForPhase("Whist")
        XCTAssertEqual(robot.currentViewer(), "east")
        XCTAssertTrue(app.buttons[UIIdentifiers.whistButton(.pass)].exists)
        XCTAssertTrue(app.buttons[UIIdentifiers.whistButton(.whist)].exists)
        XCTAssertFalse(app.buttons[UIIdentifiers.whistButton(.halfWhist)].exists)
        robot.whist(.pass)

        robot.waitForPhase("Whist")
        XCTAssertEqual(robot.currentViewer(), "south")
        XCTAssertTrue(app.buttons[UIIdentifiers.whistButton(.pass)].exists)
        XCTAssertTrue(app.buttons[UIIdentifiers.whistButton(.whist)].exists)
        XCTAssertFalse(app.buttons[UIIdentifiers.whistButton(.halfWhist)].exists)
        robot.whist(.pass)

        robot.waitForPhase("Deal complete")
        robot.waitForElement(UIIdentifiers.dealScoreDelta)
        XCTAssertEqual(robot.scoreSnapshot(for: ["north"])["north"]?.pool, 10)
        XCTAssertNil(robot.errorBanner())
    }
}
