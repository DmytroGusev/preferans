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
    /// Typed mirror of `eventLog`. The UI uses this to surface "what just
    /// happened" — the centered action banner and the per-seat last-action
    /// badge both derive from this stream, walking backward to the most
    /// recent `dealStarted` so stale actions never leak across deals.
    @Published public private(set) var recentEvents: [PreferansEvent] = []
    @Published public var selectedViewer: PlayerID
    public var viewerPolicy: ViewerPolicy
    public var dealSource: DealSource
    public let tableID: UUID = UUID()

    /// Seats that play autonomously. Human seats are absent from the map.
    public var botStrategies: [PlayerID: PlayerStrategy] = [:]

    /// Pacing between bot moves so consecutive plays don't all fire in the
    /// same frame — gives the UI room to animate. Named constants live in
    /// `BotPacing` so the lobby's test override and the picker enum can't
    /// drift on the same number.
    public var botMoveDelay: Duration = BotPacing.interactive

    /// When true (the production default), card-play events pause the UI
    /// until the human viewer taps to advance. Disabled by UI tests and by
    /// the all-bots Watch demo, where there's no human to tap.
    public var tapToAdvanceEnabled: Bool = true

    /// How long the gate waits before flipping ``idleHintActive`` to true.
    /// The UI uses the flag to escalate the "tap to continue" hint into a
    /// more prominent "Waiting for you" pulse so a player who set the
    /// device down doesn't lose the game thread.
    public var idleHintDelay: Duration = .seconds(4)

    /// When non-nil, the table is paused on a beat the human just observed
    /// (their card landing, a bot's reply, a trick completing). The UI
    /// reads ``displayProjection(revealAll:)`` to render the frozen frame
    /// and waits for ``advance()`` to move on.
    @Published public private(set) var pendingAdvance: PendingAdvance?

    /// Becomes true once the gate has been up for ``idleHintDelay``. Reset
    /// on every advance and on every action.
    @Published public private(set) var idleHintActive: Bool = false

    private var pendingBotTask: Task<Void, Never>?
    private var idleHintTask: Task<Void, Never>?

    public init(
        players: [PlayerID],
        rules: PreferansRules = .sochi,
        match: MatchSettings = .unbounded,
        firstDealer: PlayerID? = nil,
        viewerPolicy: ViewerPolicy,
        dealSource: DealSource = RandomDealSource()
    ) throws {
        self.engine = try PreferansEngine(players: players, rules: rules, match: match, firstDealer: firstDealer)
        self.viewerPolicy = viewerPolicy
        self.selectedViewer = viewerPolicy.initialViewer(among: players)
        self.dealSource = dealSource
    }

    public func send(_ action: PreferansAction) {
        do {
            // Snapshot the projection before applying so we can later
            // override the displayed phase when the engine moves past
            // `.playing` on the same step that closed a trick (last trick
            // of a deal jumps straight to `.dealScored` and the trick
            // would otherwise vanish before the user sees it).
            let preProjection = projection(revealAll: true)
            let authoritativeAction = makeAuthoritative(action)
            let events = try engine.apply(authoritativeAction)
            eventLog.append(contentsOf: events.map { String(describing: $0) })
            recentEvents.append(contentsOf: events)
            if recentEvents.count > 120 {
                recentEvents.removeFirst(recentEvents.count - 120)
            }
            lastError = nil
            lastErrorCategory = nil
            applyViewerPolicy()
            if let pending = makePendingAdvance(events: events, preProjection: preProjection) {
                pendingAdvance = pending
                startIdleHintTimer()
                pendingBotTask?.cancel()
                pendingBotTask = nil
            } else {
                clearAdvanceGate()
                scheduleBotIfNeeded()
            }
        } catch let error as PreferansError {
            lastError = error.errorDescription
            lastErrorCategory = ErrorCategory(error)
        } catch {
            lastError = error.localizedDescription
            lastErrorCategory = .system
        }
    }

    /// Resume the table after a tap-to-advance pause. Drops the freeze
    /// and lets the next bot move (if any) schedule.
    public func advance() {
        guard pendingAdvance != nil else { return }
        clearAdvanceGate()
        scheduleBotIfNeeded()
    }

    private func clearAdvanceGate() {
        pendingAdvance = nil
        idleHintActive = false
        idleHintTask?.cancel()
        idleHintTask = nil
    }

    private func startIdleHintTimer() {
        idleHintTask?.cancel()
        idleHintActive = false
        let delay = idleHintDelay
        guard delay > .zero else {
            // Tests set the delay to zero so the prominent hint shows
            // immediately and the assertion doesn't need to sleep.
            idleHintActive = true
            return
        }
        idleHintTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard self.pendingAdvance != nil else { return }
                self.idleHintActive = true
            }
        }
    }

    /// Build the pause descriptor for a freshly-applied action, or `nil`
    /// when the table should keep moving without a tap. The gate fires
    /// only on beats the viewer needs to observe — something landed on
    /// the felt that they didn't trigger themselves:
    ///
    /// * a completed trick (any closing card),
    /// * a bot's card with another bot up next (so it doesn't get
    ///   immediately replaced),
    /// * the prikup being revealed when the viewer isn't the declarer.
    ///
    /// Skipped on the viewer's own card play (they just chose it — the
    /// next beat will gate on its own merits) and on bidding / discard /
    /// whist phases (already driven by explicit user taps).
    private func makePendingAdvance(events: [PreferansEvent], preProjection: PlayerGameProjection) -> PendingAdvance? {
        guard tapToAdvanceEnabled else { return nil }
        // Watch-bots demo / all-bot table: no human to tap, just cascade.
        guard !isBotSeat(selectedViewer) else { return nil }
        var lastCardPlay: CardPlay?
        var completedTrick: Trick?
        var auctionDeclarer: PlayerID?
        for event in events {
            if case let .cardPlayed(play) = event { lastCardPlay = play }
            if case let .trickCompleted(trick) = event, completedTrick == nil { completedTrick = trick }
            if case let .auctionWon(declarer, _) = event { auctionDeclarer = declarer }
        }

        // Trick close always freezes — the viewer needs to see who won
        // before the felt sweeps and a new leader takes over.
        if let trick = completedTrick {
            // Engine has already cleared `currentTrick` and rotated the
            // leader; the projection's phase may even have moved past
            // `.playingTrick` (e.g., to `.dealScored` on the closing
            // trick of the deal). Snapshot the pre-action phase / count
            // so the override holds the felt on the completed trick.
            return PendingAdvance(
                waitingOn: selectedViewer,
                trickPlays: trick.plays,
                trickWinner: trick.winner,
                phaseOverride: preProjection.phase,
                completedTrickCountOverride: preProjection.completedTrickCount
            )
        }

        // A bot played a card and another bot is up next — freeze so
        // the viewer sees what landed before it gets buried. If the
        // viewer played the card themselves, or the viewer is the next
        // actor, no gate: the next interaction is the viewer's tap.
        if let play = lastCardPlay,
           play.player != selectedViewer,
           engine.state.currentActor.map(isBotSeat(_:)) ?? false {
            return PendingAdvance(
                waitingOn: selectedViewer,
                trickPlays: nil,
                trickWinner: nil,
                phaseOverride: nil,
                completedTrickCountOverride: nil
            )
        }

        // Auction just resolved — the prikup is now face-up on the felt.
        // Freeze so a defender viewer sees the two cards before a bot
        // declarer picks them up and they vanish into the bot's hand.
        // Skipped when the viewer is the declarer themselves: they're
        // about to discard interactively and don't need an extra tap.
        if let declarer = auctionDeclarer, declarer != selectedViewer {
            return PendingAdvance(
                waitingOn: selectedViewer,
                trickPlays: nil,
                trickWinner: nil,
                phaseOverride: nil,
                completedTrickCountOverride: nil
            )
        }

        return nil
    }

    private func isBotSeat(_ player: PlayerID) -> Bool {
        botStrategies[player] != nil
    }

    /// Variant of ``projection(revealAll:)`` that applies the active
    /// tap-to-advance freeze. Views render this so the user sees the
    /// just-played beat before the engine's follow-up state.
    public func displayProjection(revealAll: Bool = true) -> PlayerGameProjection {
        var p = projection(revealAll: revealAll)
        guard let advance = pendingAdvance else { return p }
        if let plays = advance.trickPlays {
            p.currentTrick = plays
        }
        if let winner = advance.trickWinner {
            // Roll the winner's count back to its pre-close value so the
            // tally on the felt matches what the user is staring at.
            let prev = p.trickCounts[winner] ?? 0
            p.trickCounts[winner] = max(0, prev - 1)
            if let i = p.seats.firstIndex(where: { $0.player == winner }) {
                p.seats[i].trickCount = max(0, p.seats[i].trickCount - 1)
            }
        }
        if let count = advance.completedTrickCountOverride {
            p.completedTrickCount = count
        }
        if let phase = advance.phaseOverride {
            p.phase = phase
        }
        // While the gate is up, suppress legal-action affordances so a
        // viewer who happens to be the next actor (e.g., after winning
        // a trick) can't tap a card and skip past the freeze. The first
        // tap acknowledges the beat; the second tap makes the move.
        p.legal.playableCards = []
        p.legal.settlementOptions = []
        p.legal.canAcceptSettlement = false
        p.legal.canRejectSettlement = false
        p.legal.canStartDeal = false
        return p
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
        guard pendingAdvance == nil else {
            pendingBotTask = nil
            return
        }
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

/// Tap-to-advance pause descriptor. When non-nil on the view model, the
/// table is frozen on a beat the user just watched land — their own card,
/// a bot's reply, or a completed trick. The view model holds the gate up
/// until ``GameViewModel/advance()`` is called (typically by a tap on the
/// felt). Bidding, discard, and other phases skip the gate entirely;
/// they're already driven by explicit user taps.
public struct PendingAdvance: Equatable, Sendable {
    /// Seat that must tap to advance. Today this is always the on-screen
    /// viewer; the field exists so the "Waiting for X" hint reads from a
    /// single source rather than re-deriving the seat in every view.
    public let waitingOn: PlayerID
    /// When set, render these plays as the current trick on the felt.
    /// Used after `trickCompleted` to hold the four-card trick visible
    /// even though the engine has already cleared its `currentTrick`.
    public let trickPlays: [CardPlay]?
    /// Seat that just won the trick. Used to roll the displayed
    /// trick-count back to its pre-close value while the trick is frozen.
    public let trickWinner: PlayerID?
    /// Phase to display while the gate is up. Lets the felt stay on
    /// `.playingTrick` even when the engine has moved to `.dealScored`
    /// or `.matchOver` (the closing trick of a deal).
    public let phaseOverride: ProjectedPhase?
    /// Completed-trick count to display while the gate is up. Held at the
    /// pre-close value so the auction-trail / felt indicators don't tick
    /// the trick number forward before the user has acknowledged it.
    public let completedTrickCountOverride: Int?
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
                 .illegalBid, .illegalWhist, .illegalSettlement,
                 .invalidContract, .notPlayersTurn:
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
/// - `pinned`: the viewer never moves. The only policy ever used in
///   production — every roster gets a fixed perspective so the device
///   cannot leak a bot's hand by rotating the viewer onto its seat.
/// - `followsActor`: viewer rotates to match the seat the engine is
///   currently waiting on. **Test-harness only.** UI tests opt in via the
///   launch flag so a single XCUI run can drive every seat through the
///   same hand fan. There is no user-facing hot-seat mode.
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
