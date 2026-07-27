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

    func testOnlineVariantDefaultsToOdesaAndPersists() {
        resetOnlineIdentityDefaults()

        let model = LobbyViewModel()
        XCTAssertEqual(model.onlineVariant, .odesa)
        XCTAssertEqual(model.onlineVariant.rules, .sochi)

        model.onlineVariant = .wien

        let reloaded = LobbyViewModel()
        XCTAssertEqual(reloaded.onlineVariant, .wien)
    }

    func testPulkaLimitDefaultsPersistsAndSeedsLocalMatchPerPlayer() throws {
        resetOnlineIdentityDefaults()

        let model = LobbyViewModel()
        XCTAssertEqual(model.pulkaLimit, .standard)

        model.pulkaLimit = .short
        let reloaded = LobbyViewModel()
        XCTAssertEqual(reloaded.pulkaLimit, .short)

        reloaded.startLocalTable()
        let game = try XCTUnwrap(reloaded.localModel)
        XCTAssertEqual(game.engine.match.poolTarget, 33)
    }

    func testCustomPulkaPersistsAndSeedsLocalMatchPerPlayer() throws {
        resetOnlineIdentityDefaults()

        let model = LobbyViewModel()
        model.pulkaLimit = .custom
        model.customPulkaPerPlayer = 17

        let reloaded = LobbyViewModel()
        XCTAssertEqual(reloaded.pulkaLimit, .custom)
        XCTAssertEqual(reloaded.customPulkaPerPlayer, 17)

        reloaded.setSeatCount(4)
        reloaded.startLocalTable()
        let game = try XCTUnwrap(reloaded.localModel)
        XCTAssertEqual(game.engine.match.poolTarget, 68)
    }

    func testWienVariantUsesStrictRuleProfile() {
        let rules = PreferansVariant.wien.rules

        XCTAssertTrue(rules.requireWhistOnTenTrickContracts)
        XCTAssertEqual(rules.singleWhistScoring, .gentleman)
        XCTAssertEqual(rules.failedDeclarerConsolation, .eachDefender)
        XCTAssertEqual(rules.whistResponsibility, .semiResponsible)
        XCTAssertEqual(rules.scoringMultiplier, 2)
        XCTAssertEqual(rules.zeroTricksAllPassPoolBonus, 0)
        if case let .perTrick(multiplier, amnesty) = rules.allPassPenaltyPolicy {
            XCTAssertEqual(multiplier, 2)
            XCTAssertFalse(amnesty)
        } else {
            XCTFail("Expected doubled all-pass penalties.")
        }
    }

    private func resetOnlineIdentityDefaults() {
        UserDefaults.standard.removeObject(forKey: SettingsKeys.onlineDisplayName)
        UserDefaults.standard.removeObject(forKey: SettingsKeys.onlineRegisteredAccount)
        UserDefaults.standard.removeObject(forKey: SettingsKeys.onlineAnonymousAccountID)
        UserDefaults.standard.removeObject(forKey: SettingsKeys.onlineVariant)
        UserDefaults.standard.removeObject(forKey: SettingsKeys.pulkaLimit)
        UserDefaults.standard.removeObject(forKey: SettingsKeys.customPulkaPerPlayer)
    }
}
