import Foundation
import PreferansEngine

@MainActor
public final class GameViewModel: ObservableObject {
    @Published public private(set) var engine: PreferansEngine
    @Published public private(set) var lastError: String?
    @Published public private(set) var eventLog: [String] = []
    @Published public var selectedViewer: PlayerID
    public var viewerFollowsActor: Bool
    public var dealSource: DealSource
    public let tableID: UUID = UUID()

    /// Seats that play autonomously. Human seats are absent from the map.
    public var botStrategies: [PlayerID: PlayerStrategy] = [:]

    /// Pacing between bot moves so consecutive plays don't all fire in the
    /// same frame — gives the UI room to animate.
    public var botMoveDelay: Duration = .milliseconds(500)

    private var pendingBotTask: Task<Void, Never>?

    public init(
        players: [PlayerID],
        rules: PreferansRules = .sochi,
        match: MatchSettings = .unbounded,
        firstDealer: PlayerID? = nil,
        viewerFollowsActor: Bool = false,
        dealSource: DealSource = RandomDealSource()
    ) throws {
        self.engine = try PreferansEngine(players: players, rules: rules, match: match, firstDealer: firstDealer)
        self.selectedViewer = players.first ?? PlayerID("player")
        self.viewerFollowsActor = viewerFollowsActor
        self.dealSource = dealSource
    }

    public func send(_ action: PreferansAction) {
        do {
            let authoritativeAction = makeAuthoritative(action)
            let events = try engine.apply(authoritativeAction)
            eventLog.append(contentsOf: events.map { String(describing: $0) })
            lastError = nil
            if viewerFollowsActor, let actor = currentActor(), actor != selectedViewer {
                selectedViewer = actor
            }
            scheduleBotIfNeeded()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func currentActor() -> PlayerID? {
        engine.state.currentActor
    }

    public func startDeal() {
        send(.startDeal(dealer: nil, deck: nil))
    }

    public func projection(revealAll: Bool = true) -> PlayerGameProjection {
        PlayerProjectionBuilder.projection(
            for: selectedViewer,
            tableID: tableID,
            sequence: eventLog.count,
            engine: engine,
            identities: engine.players.map { PlayerIdentity(playerID: $0, gamePlayerID: $0.rawValue, displayName: $0.rawValue) },
            policy: revealAll ? .localDebug : .online
        )
    }

    private func makeAuthoritative(_ action: PreferansAction) -> PreferansAction {
        switch action {
        case .startDeal:
            return .startDeal(dealer: engine.nextDealer, deck: dealSource.nextDeck())
        default:
            return action
        }
    }

    /// Kicks off the active bot seat's decision off the main actor and
    /// applies the resulting action when ready. A new state change
    /// supersedes any in-flight decision.
    private func scheduleBotIfNeeded() {
        pendingBotTask?.cancel()
        guard let actor = currentActor(), let strategy = botStrategies[actor] else {
            pendingBotTask = nil
            return
        }
        let snap = engine.snapshot
        let delay = botMoveDelay
        pendingBotTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            if Task.isCancelled { return }
            guard let action = await strategy.decide(snapshot: snap, viewer: actor),
                  !Task.isCancelled else { return }
            await MainActor.run {
                // The snapshot equality re-check catches the case where a
                // user input or another bot turn slipped in while we were
                // computing. Without it, a stale action could be applied
                // against a state where it's no longer legal.
                guard let self, self.engine.snapshot.state == snap.state else { return }
                self.send(action)
            }
        }
    }
}
