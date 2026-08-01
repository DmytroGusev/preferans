import Clocks
import Dependencies
import XCTest
@testable import PreferansApp
import PreferansEngine

private actor AccountClientStub: OnlineAccountServing {
    let registration: OnlineAccountRegistration
    private(set) var deletedSessionTokens: [String] = []

    init(registration: OnlineAccountRegistration) {
        self.registration = registration
    }

    func registerGuest(displayName: String) async throws -> OnlineAccountRegistration {
        registration
    }

    func registerApple(
        identityToken: String,
        nonce: String,
        displayName: String
    ) async throws -> OnlineAccountRegistration {
        registration
    }

    func deleteAccount(sessionToken: String) async throws {
        deletedSessionTokens.append(sessionToken)
    }
}

@MainActor
private final class AccountSessionStoreStub: OnlineAccountSessionStoring {
    private(set) var storedToken: String?

    func token() -> String? {
        storedToken
    }

    func store(_ token: String) -> Bool {
        storedToken = token
        return true
    }

    func remove() {
        storedToken = nil
    }
}

@MainActor
final class LobbyViewModelTests: AppTestCase {
    func testLobbyLayoutKeepsDefaultIPadTwoRegionComposition() {
        let policy = LobbyLayoutPolicy(
            isRegularWidth: true,
            usesAccessibilityText: false
        )

        XCTAssertTrue(policy.usesTabletChrome)
        XCTAssertTrue(policy.usesTwoRegionComposition)
        XCTAssertTrue(policy.stacksModeChoices)
        XCTAssertTrue(policy.placesRaspasyControlsSideBySide)
    }

    func testLobbyLayoutStacksIPadRegionsForAccessibilityText() {
        let policy = LobbyLayoutPolicy(
            isRegularWidth: true,
            usesAccessibilityText: true
        )

        XCTAssertTrue(policy.usesTabletChrome)
        XCTAssertFalse(policy.usesTwoRegionComposition)
        XCTAssertTrue(policy.stacksModeChoices)
        XCTAssertFalse(policy.placesRaspasyControlsSideBySide)
    }

    func testLobbyLayoutKeepsIPhoneSingleColumn() {
        for usesAccessibilityText in [false, true] {
            let policy = LobbyLayoutPolicy(
                isRegularWidth: false,
                usesAccessibilityText: usesAccessibilityText
            )

            XCTAssertFalse(policy.usesTabletChrome)
            XCTAssertFalse(policy.usesTwoRegionComposition)
            XCTAssertEqual(policy.stacksModeChoices, usesAccessibilityText)
            XCTAssertFalse(policy.placesRaspasyControlsSideBySide)
        }
    }

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
        XCTAssertEqual(
            (game.botStrategies["Morpheus"] as? HeuristicStrategy)?.profile,
            BotProfile(difficulty: .expert, temperament: .careful)
        )
        XCTAssertEqual(
            (game.botStrategies["Trinity"] as? HeuristicStrategy)?.profile,
            BotProfile(difficulty: .seasoned, temperament: .bold)
        )
    }

    func testBotProfileUpdatePreservesSeatKindInvariant() {
        let model = LobbyViewModel()
        let selected = BotProfile(difficulty: .casual, temperament: .adaptive)

        model.setBotProfile(selected, at: 1)
        model.setBotProfile(selected, at: 0)

        XCTAssertEqual(model.seats[1].botProfile, selected)
        XCTAssertTrue(model.seats[1].isBot)
        XCTAssertNil(model.seats[0].botProfile)
        XCTAssertFalse(model.seats[0].isBot)
    }

    func testOnlinePlayerNameIsRequiredBeforeCreateJoinOrDebugRoom() {
        resetOnlineIdentityDefaults()
        let model = LobbyViewModel()

        XCTAssertEqual(model.onlineDisplayName, "")
        XCTAssertEqual(model.onlineIdentityValidationError, "Enter your name to play online.")

        model.infoText = "stale status"
        model.startCloudflareOnlineRoom()
        XCTAssertNil(model.cloudOnlineSession)
        XCTAssertFalse(model.isOnlineRoomLoading)
        XCTAssertEqual(model.errorText, "Enter your name to play online.")
        XCTAssertNil(model.infoText)

        model.errorText = nil
        model.infoText = "stale status"
        model.onlineJoinRoomCode = "ABCD"
        model.joinCloudflareOnlineRoom()
        XCTAssertNil(model.cloudOnlineSession)
        XCTAssertFalse(model.isOnlineRoomLoading)
        XCTAssertEqual(model.errorText, "Enter your name to play online.")
        XCTAssertNil(model.infoText)

        model.errorText = nil
        model.infoText = "stale status"
        model.startInMemoryOnlineRoom()
        XCTAssertNil(model.onlineSession)
        XCTAssertEqual(model.errorText, "Enter your name to play online.")
        XCTAssertNil(model.infoText)

        // This test owns validation only. Calling the debounced persistence
        // API here can leave an ImmediateClock task racing the next test's
        // UserDefaults reset; persistence has its own clock-driven test below.
        model.onlineDisplayName = " Ada "
        XCTAssertEqual(
            model.onlineIdentityValidationError,
            "Register as a guest or sign in with Apple to play online."
        )
        XCTAssertEqual(model.currentOnlineDisplayName, "Ada")
    }

    func testOnlineDisplayNamePersistenceIsDebounced() async {
        resetOnlineIdentityDefaults()
        let clock = TestClock()
        let model = withDependencies {
            $0.continuousClock = clock
        } operation: {
            let model = LobbyViewModel()
            // Dependency values are task-local. Exercise the API while the
            // test clock is installed so the debounced task captures it,
            // instead of AppTestCase's outer ImmediateClock.
            model.setOnlineDisplayName(" A ")
            model.setOnlineDisplayName(" Ada ")
            return model
        }
        await Task.yield()

        XCTAssertEqual(model.onlineDisplayName, " Ada ")
        XCTAssertNil(UserDefaults.standard.string(forKey: SettingsKeys.onlineDisplayName))

        await clock.advance(by: LobbyViewModel.onlineNamePersistenceDelay - .milliseconds(1))
        await Task.yield()
        XCTAssertNil(UserDefaults.standard.string(forKey: SettingsKeys.onlineDisplayName))

        await clock.advance(by: .milliseconds(1))
        await Task.yield()
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: SettingsKeys.onlineDisplayName),
            "Ada"
        )
    }

    func testAccountDeletionRevokesServerBeforeClearingLobbyIdentity() async throws {
        resetOnlineIdentityDefaults()
        let registration = OnlineAccountRegistration(
            account: RegisteredOnlineAccount(
                provider: .guest,
                accountID: "guest:server-owned",
                displayName: "Ada"
            ),
            sessionToken: "pref2.account.secret"
        )
        let client = AccountClientStub(registration: registration)
        let sessionStore = AccountSessionStoreStub()
        let model = LobbyViewModel(
            accountClient: client,
            accountSessionStore: sessionStore
        )
        model.onlineDisplayName = "Ada"
        model.registerGuestOnlineAccount()
        await waitUntil { !model.isOnlineRoomLoading }

        XCTAssertEqual(model.registeredOnlineAccount, registration.account)
        XCTAssertEqual(model.onlineAccountSessionToken, registration.sessionToken)
        XCTAssertEqual(sessionStore.storedToken, registration.sessionToken)

        try await model.deleteRegisteredOnlineAccount()

        let deletedSessionTokens = await client.deletedSessionTokens
        XCTAssertEqual(deletedSessionTokens, [registration.sessionToken])
        XCTAssertNil(model.registeredOnlineAccount)
        XCTAssertNil(model.onlineAccountSessionToken)
        XCTAssertNil(sessionStore.storedToken)
        XCTAssertEqual(model.onlineDisplayName, "")
        XCTAssertEqual(model.infoText, "Online account deleted.")
        XCTAssertNil(UserDefaults.standard.data(forKey: SettingsKeys.onlineRegisteredAccount))
        XCTAssertNil(UserDefaults.standard.string(forKey: SettingsKeys.onlineDisplayName))
    }

    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        timeout: Duration = .milliseconds(750),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            await Task.yield()
        }
        XCTAssertTrue(condition(), file: file, line: line)
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
        XCTAssertEqual(game.engine.match.poolClosure, .individualWithAmericanAid)
        XCTAssertEqual(game.engine.rules, .sochi)
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

    func testCustomWienPulkaPersistsAsAnExactSharedTableTotal() throws {
        resetOnlineIdentityDefaults()

        let model = LobbyViewModel()
        model.onlineVariant = .wien
        model.pulkaLimit = .custom
        model.customPulkaTableTotal = 50

        let reloaded = LobbyViewModel()
        XCTAssertEqual(reloaded.onlineVariant, .wien)
        XCTAssertEqual(reloaded.pulkaLimit, .custom)
        XCTAssertEqual(reloaded.customPulkaTableTotal, 50)

        reloaded.startLocalTable()
        let game = try XCTUnwrap(reloaded.localModel)
        XCTAssertEqual(game.engine.match.poolTarget, 50)
        XCTAssertEqual(game.engine.match.poolClosure, .tableTotal)
    }

    func testRaspasyHouseSettingsPersistAndSeedLocalMatch() throws {
        resetOnlineIdentityDefaults()

        let model = LobbyViewModel()
        XCTAssertEqual(model.raspasyPenaltyProgression, .arithmetic)
        XCTAssertEqual(model.raspasyExitProgression, .strict)

        model.raspasyPenaltyProgression = .cappedDouble
        model.raspasyExitProgression = .constrained

        let reloaded = LobbyViewModel()
        XCTAssertEqual(reloaded.raspasyPenaltyProgression, .cappedDouble)
        XCTAssertEqual(reloaded.raspasyExitProgression, .constrained)

        reloaded.startLocalTable()
        let match = try XCTUnwrap(reloaded.localModel?.engine.match)
        XCTAssertEqual(
            match.raspasy,
            .progressive(penalties: .cappedDouble, exit: .constrained)
        )
        XCTAssertEqual(match.raspasy.scoreMultiplier(precededBy: 2), 2)
        XCTAssertEqual(match.raspasy.minimumGameTricks(after: 2), 7)
    }

    func testWienVariantUsesStrictRuleProfileAndSharedPoolClosureForLocalPlay() throws {
        resetOnlineIdentityDefaults()
        let rules = PreferansVariant.wien.rules

        XCTAssertTrue(rules.requireWhistOnTenTrickContracts)
        XCTAssertFalse(rules.forceWhistOnSixSpades)
        XCTAssertEqual(rules.singleWhistScoring, .gentleman)
        XCTAssertEqual(rules.failedDeclarerConsolation, .eachDefender)
        XCTAssertEqual(rules.whistResponsibility, .semiResponsible)
        XCTAssertEqual(rules.poolValueMultiplier, 1)
        XCTAssertEqual(rules.mountainValueMultiplier, 2)
        XCTAssertEqual(rules.whistValueMultiplier, 2)
        XCTAssertEqual(rules.poolPointWhistValue, 20)
        XCTAssertEqual(rules.mountainPointWhistValue, 10)
        XCTAssertEqual(rules.zeroTricksAllPassPoolBonus, 1)
        if case let .perTrick(multiplier, amnesty) = rules.allPassPenaltyPolicy {
            XCTAssertEqual(multiplier, 2)
            XCTAssertFalse(amnesty)
        } else {
            XCTFail("Expected doubled all-pass penalties.")
        }

        let model = LobbyViewModel()
        model.onlineVariant = .wien
        model.startLocalTable()
        let game = try XCTUnwrap(model.localModel)
        XCTAssertEqual(game.engine.rules, .leningrad)
        XCTAssertEqual(game.engine.match.poolTarget, 63)
        XCTAssertEqual(game.engine.match.poolClosure, .tableTotal)
    }

    func testCanonicalLobbyVariantsDoNotImplyStalingrad() {
        XCTAssertFalse(PreferansVariant.odesa.rules.forceWhistOnSixSpades)
        XCTAssertFalse(PreferansVariant.wien.rules.forceWhistOnSixSpades)
    }

    func testKrutyVariantUsesExplicitStalingradRules() {
        XCTAssertEqual(PreferansVariant.kruty.rules, .stalingrad)
        XCTAssertTrue(PreferansVariant.kruty.rules.forceWhistOnSixSpades)
        XCTAssertEqual(PreferansVariant.kruty.poolClosure, .individualWithAmericanAid)
        XCTAssertEqual(PreferansVariant.kruty.raspasy, .sochi)
    }

    func testThessalonikiVariantUsesExplicitRostovRules() {
        let rules = PreferansVariant.thessaloniki.rules
        XCTAssertEqual(rules, .rostov)
        XCTAssertEqual(rules.allPassTalonPolicy, .ignored)
        XCTAssertEqual(rules.allPassPenaltyPolicy, .directWhistsToLowest(pointsPerTrick: 5))
        XCTAssertEqual(rules.whistValueDivisor, 1)
        XCTAssertEqual(rules.declarerRemisePolicy, .directWhistsPerDefender(whistsPerUndertrick: 10))
        XCTAssertEqual(PreferansVariant.thessaloniki.poolClosure, .individualWithAmericanAid)
        XCTAssertEqual(PreferansVariant.thessaloniki.raspasy, .rostov)
    }

    func testLobbyRosterValidationRejectsBlankAndDuplicateNames() {
        var seats = LobbySeat.defaults(count: 3)
        XCTAssertNil(seats.validationError)

        seats[1].name = "  "
        XCTAssertEqual(seats.validationError, "Every seat needs a name.")

        seats[1].name = seats[0].name
        XCTAssertEqual(seats.validationError, "Names must be unique.")
    }

    func testOnlineCompositionResizePreservesConfiguredSeats() {
        var seats = OnlineSeatSlot.defaultComposition(count: 3)
        seats[1].kind = .bot

        let expanded = OnlineSeatSlot.resize(seats, to: 4)
        XCTAssertEqual(expanded.map(\.kind), [.you, .bot, .invite, .invite])

        let contracted = OnlineSeatSlot.resize(expanded, to: 3)
        XCTAssertEqual(contracted.map(\.kind), [.you, .bot, .invite])
        XCTAssertEqual(
            OnlineSeatSlot.canonicalPlayerIDs(count: 4),
            ["north", "east", "south", "west"]
        )
    }

    private func resetOnlineIdentityDefaults() {
        OnlineAccountSessionStore.remove()
        UserDefaults.standard.removeObject(forKey: SettingsKeys.onlineDisplayName)
        UserDefaults.standard.removeObject(forKey: SettingsKeys.onlineRegisteredAccount)
        UserDefaults.standard.removeObject(forKey: SettingsKeys.onlineAnonymousAccountID)
        UserDefaults.standard.removeObject(forKey: SettingsKeys.onlineVariant)
        UserDefaults.standard.removeObject(forKey: SettingsKeys.pulkaLimit)
        UserDefaults.standard.removeObject(forKey: SettingsKeys.customPulkaPerPlayer)
        UserDefaults.standard.removeObject(forKey: SettingsKeys.customPulkaTableTotal)
        UserDefaults.standard.removeObject(forKey: SettingsKeys.raspasyPenaltyProgression)
        UserDefaults.standard.removeObject(forKey: SettingsKeys.raspasyExitProgression)
    }
}
