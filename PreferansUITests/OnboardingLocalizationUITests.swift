import XCTest
import PreferansEngine

@MainActor
final class OnboardingLocalizationUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testRussianIntroductionThroughTheLobby() {
        checkIntroduction(language: "ru", titles: [
            "Классический преферанс — удобно и понятно", "Сыграйте полную раздачу",
            "Приглашайте друзей по коду комнаты", "Следите за пулей"
        ])
    }

    func testUkrainianIntroductionThroughTheLobby() {
        checkIntroduction(language: "uk", titles: [
            "Класичний преферанс — зручно та зрозуміло", "Зіграйте повну роздачу",
            "Запрошуйте друзів за кодом кімнати", "Стежте за кулею"
        ])
    }

    private func checkIntroduction(language: String, titles: [String]) {
        let app = XCUIApplication()
        app.launchArguments += [
            UITestFlags.showOnboarding, UITestFlags.disableAnimations,
            "-settings.appLanguage", language,
            "-AppleLanguages", "(\(language))", "-AppleLocale", language == "ru" ? "ru_RU" : "uk_UA",
        ]
        app.launch()
        let recorder = MatchScreenshotRecorder(testCase: self, app: app)
        for index in titles.indices {
            let title = app.staticTexts[UIIdentifiers.onboardingSlideTitle(index)]
            XCTAssertTrue(title.waitForExistence(timeout: 2))
            XCTAssertEqual(title.label, titles[index])
            let description = app.staticTexts[UIIdentifiers.onboardingSlideDescription(index)]
            XCTAssertTrue(description.exists)
            XCTAssertFalse(description.label.isEmpty)
            recorder.capture(name: "onboarding-\(language)-page-\(index + 1)", force: true)
            let next = app.buttons[UIIdentifiers.onboardingContinue]
            XCTAssertTrue(next.isHittable)
            next.tap()
        }
        XCTAssertTrue(app.otherElements[UIIdentifiers.screenLobby].waitForExistence(timeout: 2))
    }
}
