import XCTest
import PreferansEngine

/// Screenshot pass over the multiplayer surface: the lobby's online tab in
/// its main states, the pre-deal waiting room (via the DEBUG in-memory
/// all-bot room), and the live online table. PNGs land in
/// `$PREFERANS_SCREEN_DIR/screens-online*` so a human can eyeball the
/// online flow the same way `bin/screens` covers the local one.
@MainActor
final class OnlineScreensScreenshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    private func screenDir(_ bucket: String) -> URL {
        let root: URL
        if let override = ProcessInfo.processInfo.environment["PREFERANS_SCREEN_DIR"], !override.isEmpty {
            root = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("preferans-screens", isDirectory: true)
        }
        return root.appendingPathComponent(bucket, isDirectory: true)
    }

    /// Online lobby tab: fresh (no identity), scrolled to the room actions,
    /// with a display name, and with a pending join code surfaced.
    func testCaptureOnlineLobbyStates() {
        let screenDir = screenDir("screens-online")
        try? FileManager.default.removeItem(at: screenDir)

        let app = XCUIApplication()
        app.disableUITestAnimations()
        app.launch()
        let recorder = MatchScreenshotRecorder(
            testCase: self, app: app, outputDirectory: screenDir, filePrefix: "online")

        let onlineTab = app.buttons[UIIdentifiers.lobbyModeOnline]
        XCTAssertTrue(onlineTab.waitForExistence(timeout: 5), "Online mode tab never appeared")
        onlineTab.tap()
        recorder.capture(name: "01-online-fresh-top", force: true)

        app.swipeUp()
        recorder.capture(name: "02-online-fresh-bottom", force: true)
        app.swipeDown()

        let nameField = app.textFields[UIIdentifiers.onlineDisplayNameField]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3), "Online name field never appeared")
        // The trailing newline hits the return key, which resigns focus —
        // tapping another view does NOT dismiss the keyboard in SwiftUI.
        typeFocused(app: app, field: nameField, text: "Anya\n")
        recorder.capture(name: "03-online-named", force: true)

        app.swipeUp()
        let joinField = app.textFields[UIIdentifiers.onlineJoinRoomCode]
        XCTAssertTrue(joinField.waitForExistence(timeout: 3), "Join code field never appeared")
        typeFocused(app: app, field: joinField, text: "TABLE42\n")
        recorder.capture(name: "04-online-join-pending", force: true)
    }

    /// Tap until the keyboard is actually up, then replace the field's
    /// content. A bare `tap()` + `typeText` flakes when the tap lands while
    /// the scroll view is still settling and focus never engages; typing
    /// without select-all appends to whatever a previous run persisted.
    private func typeFocused(app: XCUIApplication, field: XCUIElement, text: String) {
        for _ in 0..<3 {
            field.tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 1.5) { break }
        }
        XCTAssertGreaterThan(app.keyboards.count, 0, "Keyboard never appeared for \(field.identifier)")
        field.press(forDuration: 1.2)
        if app.menuItems["Select All"].waitForExistence(timeout: 1.0) {
            app.menuItems["Select All"].tap()
        }
        field.typeText(text)
    }

    /// Waiting room (all-bot in-memory room), its leave-confirmation dialog,
    /// and the live table once the host starts.
    func testCaptureWaitingRoomAndLiveTable() {
        let screenDir = screenDir("screens-online-room")
        try? FileManager.default.removeItem(at: screenDir)

        let app = XCUIApplication()
        app.disableUITestAnimations()
        app.launchArguments += [UITestFlags.autoCreateInMemoryRoom]
        app.launch()
        let robot = MatchUIRobot(app: app)
        let recorder = MatchScreenshotRecorder(
            testCase: self, app: app, outputDirectory: screenDir, filePrefix: "room")

        robot.waitForElement(UIIdentifiers.screenWaitingRoom)
        robot.waitForElement(UIIdentifiers.onlineRoomCode)
        recorder.capture(name: "01-waiting-room", force: true)

        let leave = app.buttons[UIIdentifiers.buttonLeaveTable]
        if leave.waitForExistence(timeout: 3) {
            leave.tap()
            // Confirmation dialog is system chrome but worth eyeballing in
            // context. On this layout it presents as a popover whose cancel
            // ("Stay") action may be implicit — dismiss by tapping outside.
            _ = app.buttons["Leave table"].waitForExistence(timeout: 3)
            recorder.capture(name: "02-leave-confirm", force: true)
            if app.buttons["Stay"].exists {
                app.buttons["Stay"].tap()
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92)).tap()
            }
        }

        let start = app.buttons[UIIdentifiers.onlineStartGame]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "Start button never appeared")
        XCTAssertTrue(
            start.isHittable || waitUntilHittable(start, timeout: 5),
            "Start button never became hittable (dialog still up?)")
        start.tap()
        robot.waitForElement(UIIdentifiers.screenGame)
        recorder.capture(name: "03-live-table", force: true)

        // Room section of the overflow menu (code + share invite).
        let overflow = app.buttons[UIIdentifiers.overflowMenu]
        if overflow.waitForExistence(timeout: 3) {
            overflow.tap()
            usleep(300_000)
            recorder.capture(name: "04-live-table-menu", force: true)
        }
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "isHittable == true")
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [exp], timeout: timeout) == .completed
    }
}
