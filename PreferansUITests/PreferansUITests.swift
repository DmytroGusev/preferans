import XCTest

final class PreferansUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testLobbyRenders() {
        let app = XCUIApplication()
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

    func testGameScreenShowsCoreSectionsAfterDeal() {
        let app = XCUIApplication()
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
