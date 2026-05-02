import Foundation
import PreferansEngine

@MainActor
public final class GameViewModel: ObservableObject {
    @Published public private(set) var engine: PreferansEngine
    @Published public private(set) var lastError: String?
    /// Category of the most recent error, or `nil` when there was none.
    /// The UI uses this to decide whether to show the banner — categories
    /// the user can already see from inline visual state (illegal-card
    /// outline, only-legal buttons) don't get a redundant banner. Tests
    /// still see the error in `lastError` regardless.
    @Published public private(set) var lastErrorCategory: ErrorCategory?
    @Published public private(set) var eventLog: [String] = []
    @Published public var selectedViewer: PlayerID
    public var viewerPolicy: ViewerPolicy
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
        viewerPolicy: ViewerPolicy = .followsActor,
        dealSource: DealSource = RandomDealSource()
    ) throws {
        self.engine = try PreferansEngine(players: players, rules: rules, match: match, firstDealer: firstDealer)
        self.viewerPolicy = viewerPolicy
        self.selectedViewer = viewerPolicy.initialViewer(among: players)
        self.dealSource = dealSource
    }

    public func send(_ action: PreferansAction) {
        do {
            let authoritativeAction = makeAuthoritative(action)
            let events = try engine.apply(authoritativeAction)
            eventLog.append(contentsOf: events.map { String(describing: $0) })
            lastError = nil
            lastErrorCategory = nil
            applyViewerPolicy()
            scheduleBotIfNeeded()
        } catch let error as PreferansError {
            lastError = error.errorDescription
            lastErrorCategory = ErrorCategory(error)
        } catch {
            lastError = error.localizedDescription
            lastErrorCategory = .system
        }
    }

    /// The error message that should be surfaced to the user as a banner,
    /// or `nil` when the most recent error is one the UI already
    /// communicates inline (legal-card outline, only-legal buttons,
    /// pre-Start lobby validation). Tests can still read `lastError`
    /// directly to verify engine-level rejection behavior.
    public var displayableError: String? {
        guard let category = lastErrorCategory, category.shouldDisplayBanner else { return nil }
        return lastError
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

    private func applyViewerPolicy() {
        switch viewerPolicy {
        case .pinned:
            // Pinned viewer never moves. The user can still swap manually
            // via the "View as" picker — that path writes selectedViewer
            // directly and bypasses this hook.
            break
        case .followsActor:
            if let actor = currentActor(), actor != selectedViewer {
                selectedViewer = actor
            }
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

extension GameViewModel {
    /// Classifies the most recent engine error so the view layer can decide
    /// whether to surface a banner. Information the user can already see
    /// inline (legal-card outlines, only-legal buttons, lobby validation
    /// gating) gets `.uiValidatable` and is suppressed; everything else
    /// surfaces so a real bug isn't silently swallowed.
    public enum ErrorCategory: Sendable {
        case uiValidatable
        case system

        init(_ error: PreferansError) {
            switch error {
            case .illegalCardPlay, .cardNotInHand, .duplicateCards,
                 .illegalBid, .illegalWhist, .invalidContract, .notPlayersTurn:
                self = .uiValidatable
            case .invalidPlayer, .invalidPlayers, .invalidDeck, .invalidState:
                self = .system
            }
        }

        var shouldDisplayBanner: Bool {
            switch self {
            case .uiValidatable: return false
            case .system: return true
            }
        }
    }
}

/// How the on-screen viewer (whose hand is rendered face-up at the bottom)
/// should change in response to gameplay.
///
/// - `pinned`: the viewer never moves. Use when there is exactly one human
///   at the table — the device shows that human's seat and bots play their
///   turns without ever revealing their hands.
/// - `followsActor`: viewer rotates to match the seat the engine is
///   currently waiting on. Use for hot-seat play (every seat is a human
///   passing the device around), so each player sees their own hand on
///   their turn without diving into the debug picker.
public enum ViewerPolicy: Equatable, Sendable {
    case pinned(PlayerID)
    case followsActor

    func initialViewer(among players: [PlayerID]) -> PlayerID {
        switch self {
        case let .pinned(seat):
            return seat
        case .followsActor:
            return players.first ?? PlayerID("player")
        }
    }
}
