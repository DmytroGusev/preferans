import XCTest
@testable import PreferansApp
import PreferansEngine

@MainActor
final class LobbyViewModelTests: AppTestCase {
    func testBotStepperAddsAndRemovesFourthBot() {
        let model = LobbyViewModel()

        XCTAssertEqual(model.seats.count, 3)
        XCTAssertEqual(model.botCount, 2)
        XCTAssertTrue(model.canAddBot)
        XCTAssertFalse(model.canRemoveBot)

        model.addBot()

        XCTAssertEqual(model.seats.count, 4)
        XCTAssertEqual(model.botCount, 3)
        XCTAssertEqual(model.seats.last?.name, "Agent Smith")
        XCTAssertFalse(model.canAddBot)
        XCTAssertTrue(model.canRemoveBot)

        model.removeBot()

        XCTAssertEqual(model.seats.count, 3)
        XCTAssertEqual(model.botCount, 2)
        XCTAssertTrue(model.canAddBot)
        XCTAssertFalse(model.canRemoveBot)
    }

    func testStartLocalTableAssignsBotStrategiesFromRoster() throws {
        let model = LobbyViewModel()

        model.startLocalTable()

        let game = try XCTUnwrap(model.localModel)
        XCTAssertNil(model.errorText)
        XCTAssertNotNil(game.botStrategies["Morpheus"])
        XCTAssertNotNil(game.botStrategies["Trinity"])
        XCTAssertNil(game.botStrategies["Neo"])
    }

    func testOnlinePlayerNameIsRequiredBeforeCreateJoinOrDebugRoom() {
        resetOnlineIdentityDefaults()
        let model = LobbyViewModel()

        XCTAssertEqual(model.onlineDisplayName, "")
        XCTAssertEqual(model.onlineIdentityValidationError, "Enter your name to play online.")

        model.startCloudflareOnlineRoom()
        XCTAssertNil(model.cloudOnlineSession)
        XCTAssertFalse(model.isOnlineRoomLoading)
        XCTAssertEqual(model.errorText, "Enter your name to play online.")

        model.errorText = nil
        model.onlineJoinRoomCode = "ABCD"
        model.joinCloudflareOnlineRoom()
        XCTAssertNil(model.cloudOnlineSession)
        XCTAssertFalse(model.isOnlineRoomLoading)
        XCTAssertEqual(model.errorText, "Enter your name to play online.")

        model.errorText = nil
        model.startInMemoryOnlineRoom()
        XCTAssertNil(model.onlineSession)
        XCTAssertEqual(model.errorText, "Enter your name to play online.")

        model.setOnlineDisplayName(" Ada ")
        XCTAssertNil(model.onlineIdentityValidationError)
        XCTAssertEqual(model.currentOnlineDisplayName, "Ada")
    }

    private func resetOnlineIdentityDefaults() {
        UserDefaults.standard.removeObject(forKey: SettingsKeys.onlineDisplayName)
        UserDefaults.standard.removeObject(forKey: SettingsKeys.onlineRegisteredAccount)
        UserDefaults.standard.removeObject(forKey: SettingsKeys.onlineAnonymousAccountID)
    }
}
