import XCTest

final class PreferansUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testLobbyRenders() {
        let app = XCUIApplication()
        app.disableUITestAnimations()
        app.launch()

        XCTAssertTrue(app.staticTexts["Preferans"].firstMatch.waitForExistence(timeout: 5),
                      "Lobby should display the Preferans title")
        XCTAssertTrue(app.staticTexts["Local table players"].waitForExistence(timeout: 2),
                      "Lobby should show the local table players section")
        XCTAssertTrue(app.buttons["Start Local Table"].exists,
                      "Lobby should expose the Start Local Table action")
        XCTAssertTrue(app.buttons["3 players"].exists)
        XCTAssertTrue(app.buttons["4 players"].exists)
    }

    func testStartLocalTableThenDeal() {
        let app = XCUIApplication()
        app.disableUITestAnimations()
        app.launch()

        let startLocal = app.buttons["Start Local Table"]
        XCTAssertTrue(startLocal.waitForExistence(timeout: 5))
        startLocal.tap()

        let startDeal = app.buttons["Start Deal"]
        XCTAssertTrue(startDeal.waitForExistence(timeout: 5),
                      "Game screen should expose Start Deal once the local table opens")

        startDeal.tap()

        let biddingTitle = app.staticTexts["Bidding"]
        XCTAssertTrue(biddingTitle.waitForExistence(timeout: 5),
                      "Phase title should switch to Bidding once the deal starts")

        let talonHeader = app.staticTexts["Talon"]
        XCTAssertTrue(talonHeader.waitForExistence(timeout: 2),
                      "Talon section should be visible after the deal")
    }

    func testFourPlayerRosterAddsSeat() {
        let app = XCUIApplication()
        app.disableUITestAnimations()
        app.launch()

        XCTAssertTrue(app.buttons["4 players"].waitForExistence(timeout: 5))
        app.buttons["4 players"].tap()

        let textFields = app.textFields
        XCTAssertGreaterThanOrEqual(textFields.count, 4,
                                    "Switching to 4 players should add a fourth roster row")
    }

    func testBiddingExposesPassAndMisereOptions() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestViewerFollowsActor"]
        app.disableUITestAnimations()
        app.launch()

        app.buttons["Start Local Table"].tap()
        XCTAssertTrue(app.buttons["Start Deal"].waitForExistence(timeout: 5))
        app.buttons["Start Deal"].tap()

        XCTAssertTrue(app.staticTexts["Bidding"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Bid"].waitForExistence(timeout: 2),
                      "Bidding panel should expose its Bid header")
        XCTAssertTrue(app.buttons["Pass"].exists, "Bid call list must include Pass")
        XCTAssertTrue(app.buttons["Misere"].exists, "Bid call list must include Misere")
    }

    func testAllPassDrivesEngineIntoPlayingPhase() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestViewerFollowsActor"]
        app.disableUITestAnimations()
        app.launch()

        app.buttons["Start Local Table"].tap()
        XCTAssertTrue(app.buttons["Start Deal"].waitForExistence(timeout: 5))
        app.buttons["Start Deal"].tap()

        XCTAssertTrue(app.staticTexts["Bidding"].waitForExistence(timeout: 5))

        for index in 0..<3 {
            let pass = app.buttons["Pass"].firstMatch
            XCTAssertTrue(pass.waitForExistence(timeout: 3),
                          "Pass should remain offered for bidder #\(index + 1)")
            pass.tap()
        }

        XCTAssertTrue(app.staticTexts["Playing"].waitForExistence(timeout: 5),
                      "Phase title should switch to Playing once all three players pass out")
        XCTAssertFalse(app.staticTexts["Bidding"].exists,
                       "Bidding header should be gone once all-pass play begins")
    }

    func testDeterministicScenarioPinsFirstBidderAndDealtCards() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTestViewerFollowsActor",
            "-uiTestFirstDealer", "south",
            "-uiTestDealScenario", "sortedDeck"
        ]
        app.disableUITestAnimations()
        app.launch()

        app.buttons["Start Local Table"].tap()
        XCTAssertTrue(app.buttons["Start Deal"].waitForExistence(timeout: 5))
        app.buttons["Start Deal"].tap()

        // sortedDeck + dealer=south -> activePlayers=[north, east, south],
        // first bidder = north, talon = ♠K, ♠A.
        XCTAssertTrue(app.staticTexts["Bidding"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Auction: north to call."].exists,
                      "Pinned dealer should put north on the bid")
        XCTAssertTrue(app.staticTexts["You are: north"].exists,
                      "viewerFollowsActor should rotate the viewer to north")
        XCTAssertTrue(app.staticTexts["K♠"].exists,
                      "Sorted-deck talon must include the ♠K")
        XCTAssertTrue(app.staticTexts["A♠"].exists,
                      "Sorted-deck talon must include the ♠A")
    }

    func testNorthSpadesSixScenarioDrivesEngineToDiscardWindow() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTestViewerFollowsActor",
            "-uiTestFirstDealer", "south",
            "-uiTestDealScenario", "northBidsSpadesSix"
        ]
        app.disableUITestAnimations()
        app.launch()

        app.buttons["Start Local Table"].tap()
        XCTAssertTrue(app.buttons["Start Deal"].waitForExistence(timeout: 5))
        app.buttons["Start Deal"].tap()

        // North's hand has the ♠A pinned in this scenario, so the bid panel
        // must offer "6♠".
        XCTAssertTrue(app.staticTexts["Bidding"].waitForExistence(timeout: 5))
        let sixSpades = app.buttons["6♠"]
        XCTAssertTrue(sixSpades.waitForExistence(timeout: 2),
                      "6♠ must be a legal opening bid for north")
        sixSpades.tap()

        // East and south must each pass to advance auction.
        for label in ["east", "south"] {
            XCTAssertTrue(app.staticTexts["Auction: \(label) to call."].waitForExistence(timeout: 3))
            app.buttons["Pass"].firstMatch.tap()
        }

        // Auction won — declarer takes the talon and the discard panel opens.
        XCTAssertTrue(app.staticTexts["Talon exchange"].waitForExistence(timeout: 5),
                      "Phase title should switch to Talon exchange once auction is won")
        XCTAssertTrue(app.staticTexts["Select exactly two cards to discard"].exists,
                      "Discard prompt should appear for the declarer")
    }

    func testGameScreenShowsCoreSectionsAfterDeal() {
        let app = XCUIApplication()
        app.disableUITestAnimations()
        app.launch()

        app.buttons["Start Local Table"].tap()
        XCTAssertTrue(app.buttons["Start Deal"].waitForExistence(timeout: 5))
        app.buttons["Start Deal"].tap()

        XCTAssertTrue(app.staticTexts["Bidding"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Current trick"].exists,
                      "Game screen should always render the Current trick panel")
        XCTAssertTrue(app.staticTexts["Talon"].exists,
                      "Game screen should always render the Talon panel")
        XCTAssertTrue(app.staticTexts["Discard"].exists,
                      "Game screen should always render the Discard panel")
        XCTAssertTrue(app.staticTexts["Table"].exists,
                      "Game screen should always render the Table panel")
        XCTAssertTrue(app.staticTexts["Log"].exists,
                      "Game screen should always render the event Log panel")
    }
}
