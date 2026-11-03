import XCTest
import PreferansEngine
@testable import PreferansApp

@MainActor
private final class AnalyticsRecorder: AppAnalyticsSink {
    var starts = 0
    var resets = 0
    var canStart = true
    var events: [AppAnalyticsEvent] = []
    func enable() -> Bool { starts += 1; return canStart }
    func disableAndReset() { resets += 1 }
    func log(_ event: AppAnalyticsEvent) { events.append(event) }
}

@MainActor
final class AppAnalyticsTests: XCTestCase {
    private func fixture() -> (AppAnalytics, AnalyticsRecorder, UserDefaults) {
        let name = "PreferansAnalyticsTests.\(UUID())"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        let defaults = UserDefaults(suiteName: name)!
        let sink = AnalyticsRecorder()
        return (AppAnalytics(defaults: defaults, sink: sink, automation: false), sink, defaults)
    }

    func testUnknownConsentDoesNotStartOrBufferEvents() {
        let (analytics, sink, _) = fixture()
        analytics.startIfAllowed()
        analytics.track(.onboardingCompleted)
        XCTAssertTrue(analytics.shouldAsk)
        XCTAssertEqual(sink.starts, 0)
        analytics.setAllowed(true)
        XCTAssertEqual(sink.events, [.consentGranted])
    }

    func testExplicitOptInStartsOnceAndRecordsOnlyTypedEvents() {
        let (analytics, sink, _) = fixture()
        analytics.setAllowed(true)
        analytics.startIfAllowed()
        analytics.track(.onlineRoom(.create, .succeeded))
        XCTAssertEqual(sink.starts, 1)
        XCTAssertEqual(sink.events.last?.name, "online_room_flow")
        XCTAssertEqual(sink.events.last?.parameters["operation"] as? String, "create")
        XCTAssertFalse(analytics.shouldAsk)
    }

    func testDecliningPersistsAcrossLaunches() {
        let (analytics, sink, defaults) = fixture()
        analytics.setAllowed(false)
        let next = AppAnalytics(defaults: defaults, sink: sink, automation: false)
        next.startIfAllowed()
        next.track(.onboardingCompleted)
        XCTAssertEqual(next.choice, .denied)
        XCTAssertEqual(sink.starts, 0)
        XCTAssertTrue(sink.events.isEmpty)
    }

    func testWithdrawalResetsIdentityReceiptsAndBlocksEvents() {
        let (analytics, sink, defaults) = fixture()
        analytics.setAllowed(true)
        analytics.trackOnce(.onboardingCompleted, table: UUID(), revision: 1)
        XCTAssertNotNil(defaults.array(forKey: AppAnalytics.receiptKey))
        analytics.setAllowed(false)
        analytics.track(.onboardingCompleted)
        XCTAssertEqual(sink.resets, 1)
        XCTAssertFalse(analytics.isOperational)
        XCTAssertNil(defaults.array(forKey: AppAnalytics.receiptKey))
        XCTAssertEqual(sink.events.count, 2)
    }

    func testAutomationNeverStartsSDKDespiteStoredConsent() {
        let (_, sink, defaults) = fixture()
        defaults.set(AnalyticsChoice.allowed.rawValue, forKey: AppAnalytics.choiceKey)
        let analytics = AppAnalytics(defaults: defaults, sink: sink, automation: true)
        analytics.startIfAllowed()
        analytics.track(.onboardingCompleted)
        XCTAssertEqual(sink.starts, 0)
        XCTAssertTrue(sink.events.isEmpty)
        XCTAssertFalse(analytics.shouldAsk)
    }

    func testConfigurationFailureIsVisibleAndDropsEvents() {
        let (analytics, sink, _) = fixture()
        sink.canStart = false
        analytics.setAllowed(true)
        analytics.track(.onboardingCompleted)
        XCTAssertFalse(analytics.isOperational)
        XCTAssertTrue(sink.events.isEmpty)
    }

    func testReconnectDuplicateIsSuppressedAcrossLaunchesWithoutSendingTableID() {
        let (analytics, sink, defaults) = fixture()
        let table = UUID()
        let event = AppAnalyticsEvent.matchStarted(.init(mode: .online, players: 3, bots: 1, rules: .sochi))
        analytics.setAllowed(true)
        analytics.trackOnce(event, table: table, revision: 1)
        analytics.trackOnce(event, table: table, revision: 1)
        let next = AppAnalytics(defaults: defaults, sink: sink, automation: false)
        next.startIfAllowed()
        next.trackOnce(event, table: table, revision: 1)
        XCTAssertEqual(sink.events.filter { $0.name == "match_start" }.count, 1)
        XCTAssertEqual(Set(event.parameters.keys), ["game_mode", "player_count", "bot_count", "convention"])
        XCTAssertFalse((defaults.stringArray(forKey: AppAnalytics.receiptKey) ?? []).joined().contains(table.uuidString))
    }

    func testOnlyFirstDealCountsAsMatchStartAndPrivateEventsAreIgnored() {
        let (analytics, sink, _) = fixture()
        analytics.setAllowed(true)
        let table = UUID()
        let events: [PreferansEvent] = [.dealStarted(dealer: PlayerID("SECRET"), activePlayers: [])]
        let context = AnalyticsGameContext(mode: .online, players: 4, bots: 2, rules: .leningrad)
        analytics.recordGameEvents(events, table: table, revision: 1, context: context)
        analytics.recordGameEvents(events, table: table, revision: 10, context: context)
        XCTAssertEqual(sink.events.filter { $0.name == "match_start" }.count, 1)
        XCTAssertFalse(String(describing: sink.events).contains("SECRET"))
    }

    func testMetricsAreBoundedAndConventionsMatchPublicLabels() {
        let context = AnalyticsGameContext(mode: .local, players: Int.max, bots: Int.max, rules: .rostov)
        XCTAssertEqual(context.players, 4)
        XCTAssertEqual(context.bots, 4)
        XCTAssertEqual(context.convention, "berlin")
        let event = AppAnalyticsEvent.matchCompleted(context, deals: Int.max)
        XCTAssertEqual(event.parameters["deals_played"] as? Int, 10000)
        XCTAssertEqual(AppAnalyticsEvent.botSeat(.add, .succeeded, .expert).parameters["difficulty"] as? String, "expert")
    }

    func testFinalDealAndMatchCompletionRemainDistinctButEachDeduplicates() {
        let (analytics, sink, _) = fixture()
        analytics.setAllowed(true)
        let table = UUID()
        let context = AnalyticsGameContext(mode: .online, players: 3, bots: 1, rules: .sochi)
        for _ in 0..<2 {
            analytics.trackOnce(.dealCompleted(context, .allPass), table: table, revision: 80)
            analytics.trackOnce(.matchCompleted(context, deals: 6), table: table, revision: 80)
        }
        XCTAssertEqual(sink.events.filter { $0.name == "deal_complete" }.count, 1)
        XCTAssertEqual(sink.events.filter { $0.name == "match_complete" }.count, 1)
    }
}
