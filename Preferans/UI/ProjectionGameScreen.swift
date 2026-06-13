import SwiftUI
import PreferansEngine

public struct ProjectionGameScreen<Menu: View>: View {
    public var projection: PlayerGameProjection
    public var eventLog: [String]
    /// Typed mirror of `eventLog`. Drives the centered action banner and
    /// the per-seat last-action badge. Optional for callers that don't
    /// have access to the typed stream — they get the legacy UX without
    /// notifications.
    public var recentEvents: [PreferansEvent]
    /// Active tap-to-advance pause descriptor. When non-nil, the felt
    /// shows a "tap to continue" overlay and any tap on the table area
    /// invokes `onTapToAdvance`.
    public var pendingAdvance: PendingAdvance?
    /// Set to true once the pause has been up long enough that the table
    /// should escalate the hint into a more prominent "Waiting for you"
    /// pulse. The felt overlay reads this flag to switch styling.
    public var idleHintActive: Bool
    public var onSend: (PreferansAction) -> Void
    /// Invoked when the user taps the felt during a tap-to-advance pause.
    /// `nil` outside of local play (online tables don't gate per-tap).
    public var onTapToAdvance: (() -> Void)?
    /// When non-nil, renders an explicit "Leave table" button in the header
    /// and a "Back to lobby" CTA on the game-over card so the user always
    /// has a one-tap exit.
    public var onLeaveTable: (() -> Void)?
    /// When non-nil, the game-over card shows a "Rematch" CTA that triggers
    /// this closure (resets the engine and starts a new match with the same
    /// roster).
    public var onRematch: (() -> Void)?
    private let extraMenu: Menu

    private enum Sheet: String, Identifiable {
        case score, log, settings, lastTrick
        var id: String { rawValue }
    }

    @State private var selectedDiscard: Set<Card> = []
    @State private var selectedPlayCard: Card?
    @State private var talonTakenSequence: Int?
    @State private var activeSheet: Sheet?
    @State private var showLeaveConfirm = false
    @AppStorage(SettingsKeys.cardSuitDisplayOrder) private var cardSuitDisplayOrderRaw: String = CardSuitDisplayOrder.default.rawValue
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Namespace private var cardNamespace

    public init(
        projection: PlayerGameProjection,
        eventLog: [String] = [],
        recentEvents: [PreferansEvent] = [],
        pendingAdvance: PendingAdvance? = nil,
        idleHintActive: Bool = false,
        onSend: @escaping (PreferansAction) -> Void,
        onTapToAdvance: (() -> Void)? = nil,
        onLeaveTable: (() -> Void)? = nil,
        onRematch: (() -> Void)? = nil,
        @ViewBuilder extraMenu: () -> Menu = { EmptyView() }
    ) {
        self.projection = projection
        self.eventLog = eventLog
        self.recentEvents = recentEvents
        self.pendingAdvance = pendingAdvance
        self.idleHintActive = idleHintActive
        self.onSend = onSend
        self.onTapToAdvance = onTapToAdvance
        self.onLeaveTable = onLeaveTable
        self.onRematch = onRematch
        self.extraMenu = extraMenu()
    }

    private var seatActions: [PlayerID: RecentAction] {
        RecentActionFeed.perSeat(from: recentEvents)
    }

    private var bannerAction: RecentAction? {
        RecentActionFeed.banner(from: recentEvents)
    }

    private var activityEntries: [ActivityLogEntry] {
        ActivityLogFeed.entries(from: recentEvents, displayName: projection.displayName(for:))
    }

    /// Per-seat contract-role pill keyed by PlayerID. Computed once per
    /// render so every seat view doesn't re-derive the same dictionary
    /// from the projection.
    private var seatRoleBadges: [PlayerID: SeatRoleBadge] {
        var result: [PlayerID: SeatRoleBadge] = [:]
        for seat in projection.seats {
            if let badge = projection.roleBadge(for: seat.player) {
                result[seat.player] = badge
            }
        }
        return result
    }

    private var cardSuitDisplayOrder: CardSuitDisplayOrder {
        CardSuitDisplayOrder(rawValue: cardSuitDisplayOrderRaw) ?? .default
    }

    public var body: some View {
        Group {
            if isCompactLandscape {
                landscapeBody
            } else if horizontalSizeClass == .compact {
                compactBody
            } else {
                regularBody
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.screenGame)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .score:      scoreSheet
            case .log:        logSheet
            case .settings:   SettingsScreen()
            case .lastTrick:  lastTrickSheet
            }
        }
        .onChange(of: projection.sequence) { _, _ in
            // Game-over rendering is now inline on the felt — see
            // `TableView.gameOverCard`. No modal auto-presentation here.
            reconcileTalonTakeState()
            reconcileDiscardSelection()
            reconcilePlaySelection()
        }
    }

    // MARK: - Compact (iPhone)

    private var compactBody: some View {
        VStack(spacing: 0) {
            headerStrip
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 8)
            tableView(seatRoleBadges: seatRoleBadges)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if shouldShowHandRail {
                viewerHandFan
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 4)
                    .layoutPriority(1)
            }
            if shouldShowActionBar {
                ActionBarView(projection: projection, selectedDiscard: selectedDiscard, onSend: onSend)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .feltBackground()
    }

    // MARK: - Compact landscape (iPhone landscape)

    /// iPhone landscape: vertical real estate is tight, horizontal is
    /// abundant. Three columns: opponent fans on the left, trick + state
    /// in the center (the action bar tucks under it), viewer hand spans
    /// the bottom of the right column. Maximizes the felt without losing
    /// the chip rail.
    private var landscapeBody: some View {
        VStack(spacing: 0) {
            headerStrip
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 4)
            HStack(alignment: .top, spacing: 8) {
                landscapeOpponentColumn
                    .frame(width: hasOpenOpponentHand ? 260 : 180)
                VStack(spacing: 4) {
                    DealStateStrip(projection: projection)
                    landscapeTablePlayArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if shouldShowActionBar {
                        ActionBarView(projection: projection, selectedDiscard: selectedDiscard, onSend: onSend)
                    }
                    if shouldShowHandRail {
                        viewerHandFan
                            .padding(.horizontal, 4)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .feltBackground()
    }

    private var landscapeOpponentColumn: some View {
        VStack(spacing: 6) {
            ForEach(orderedOpponentSeats) { seat in
                OpponentSeatView(
                    seat: seat,
                    orientation: .top,
                    cardSuitOrder: cardSuitDisplayOrder,
                    contractBid: projection.activeContractBid(for: seat.player),
                    isDeemphasized: hasOpenOpponentHand && !isOpenHand(seat),
                    lastAction: seatActions[seat.player],
                    roleBadge: seatRoleBadges[seat.player],
                    seatOrder: seatOrderNumber(for: seat.player),
                    showsTrickCount: seat.trickCount > 0 || isPlayingPhase,
                    playableCards: playableCards(for: seat.player),
                    selectedCards: selectedCards(for: seat.player),
                    onSelectCard: cardSelectHandler(for: seat.player),
                    onPlayCard: cardPlayHandler(for: seat.player),
                    onDragCard: cardPlayHandler(for: seat.player)
                )
            }
            Spacer(minLength: 0)
        }
    }

    /// Trick area only — no opponent row (the column on the left owns
    /// that). Reuses the same TableView play-area branch as portrait.
    @ViewBuilder
    private var landscapeTablePlayArea: some View {
        tableView(renderOpponentsAtTop: false)
    }

    /// Single source of truth for the TableView trailing arguments.
    /// Every layout (compact, landscape, regular) passes the same
    /// projection / handlers / pause state — only `renderOpponentsAtTop`
    /// and `seatRoleBadges` vary.
    private func tableView(renderOpponentsAtTop: Bool = true,
                           seatRoleBadges: [PlayerID: SeatRoleBadge] = [:]) -> TableView {
        // The method reference `advanceToNextDeal` trips a Swift 6
        // type-checker bug here ("failed to produce diagnostic for
        // expression"); wrapping in an explicit closure sidesteps it
        // and is equivalent at the call site.
        let advance: () -> Void = { advanceToNextDeal() }
        return TableView(
            projection: projection,
            animationNamespace: cardNamespace,
            onAdvance: advance,
            onStartDeal: shouldShowCenterDealCTA ? advance : nil,
            onLeaveTable: onLeaveTable,
            onRematch: onRematch,
            renderOpponentsAtTop: renderOpponentsAtTop,
            seatActions: seatActions,
            seatRoleBadges: seatRoleBadges,
            bannerAction: bannerAction,
            pendingAdvance: pendingAdvance,
            idleHintActive: idleHintActive,
            isTalonTakePending: isTalonTakePending,
            cardSuitOrder: cardSuitDisplayOrder,
            selectedPlayCard: selectedPlayCard,
            onSelectPlayCard: selectPlayCard,
            onPlayCard: { owner, card in playCard(card, from: owner) },
            onTakeTalon: takeTalon,
            onTapToAdvance: onTapToAdvance
        )
    }

    private var orderedOpponentSeats: [SeatProjection] {
        projection.tableClockwiseOpponentSeats
    }

    /// True when at least one active opponent has a revealed hand —
    /// drives the wider opponent column in compact landscape so the
    /// open-hand fan doesn't overflow the column.
    private var hasOpenOpponentHand: Bool {
        orderedOpponentSeats.contains { seat in
            seat.role != .sittingOut && seat.hand.contains { $0.knownCard != nil }
        }
    }

    private func isOpenHand(_ seat: SeatProjection) -> Bool {
        seat.hand.contains { $0.knownCard != nil }
    }

    /// True when the device is in compact landscape (iPhone rotated). Used
    /// to switch to a side-by-side layout that fits the felt + hand into
    /// the limited vertical real estate.
    private var isCompactLandscape: Bool {
        horizontalSizeClass == .compact && verticalSizeClass == .compact
    }

    // MARK: - Regular (iPad / wider)

    private var regularBody: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                headerStrip
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
                tableView()
                    .frame(maxHeight: .infinity)
                if shouldShowHandRail {
                    viewerHandFan
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                }
                if shouldShowActionBar {
                    ActionBarView(projection: projection, selectedDiscard: selectedDiscard, onSend: onSend)
                }
            }
            .frame(maxWidth: .infinity)
            ScoreBoardView(score: projection.score, displayName: projection.displayName(for:))
                .frame(width: 360)
        }
        .padding(.vertical, 16)
        .padding(.trailing, 16)
        .feltBackground()
    }

    /// True while the felt is rendering the deal-summary card. The summary
    /// owns the "Next deal" CTA, so the bottom action bar is suppressed
    /// while the summary is up.
    private var isDealFinishedPhase: Bool {
        if case .dealFinished = projection.phase { return true }
        return false
    }

    /// True when the screen should put a single, centered Deal CTA on the
    /// felt (pre-first-deal idle state). When this is true, the action bar
    /// hides its own start-deal row to avoid two CTAs for the same intent.
    private var shouldShowCenterDealCTA: Bool {
        guard projection.legal.canStartDeal else { return false }
        if case .waitingForDeal = projection.phase { return true }
        return false
    }

    /// Bottom action bar visibility. Hidden whenever the felt itself owns
    /// the screen's primary affordance: the deal-summary card (Next deal),
    /// the idle Deal CTA, or the inline game-over standings card.
    private var shouldShowActionBar: Bool {
        if isDealFinishedPhase { return false }
        if shouldShowCenterDealCTA { return false }
        if isTalonTakePending { return false }
        if case .gameOver = projection.phase { return false }
        return true
    }

    /// Hand rail visibility. The rail is purely decorative when the viewer
    /// has nothing to play (pre-deal idle, deal scored, match over, sitting
    /// out a 4-player deal) — keep it offscreen so the felt isn't permanently
    /// haunted by an empty pill at the bottom.
    private var shouldShowHandRail: Bool {
        guard let seat = viewerSeat else { return false }
        if case .gameOver = projection.phase { return false }
        if case .dealFinished = projection.phase { return false }
        if shouldShowCenterDealCTA { return false }
        // Sitting-out seats hold no cards and have no action — same logic.
        if seat.role == .sittingOut, !projection.legal.canDiscard { return false }
        return !seat.hand.isEmpty || projection.legal.canDiscard
    }

    private func advanceToNextDeal() {
        onSend(.startDeal(dealer: nil, deck: nil))
    }

    // MARK: - Header strip
    //
    // Replaces both the old phaseStatusBar and the toolbar pill. One row:
    // a small phase chip on the left, a single overflow menu on the right.
    // Score / event log / settings / View-as all live behind that one
    // ellipsis button instead of competing for top-of-screen real estate.

    private var headerStrip: some View {
        HStack(alignment: .center, spacing: 8) {
            phaseChip
            Spacer(minLength: 8)
            // The icons own their spacing via 40 pt hit frames; extra
            // HStack spacing here would push the phase chip into
            // truncation on compact widths.
            HStack(spacing: 0) {
                if projection.lastCompletedTrick != nil {
                    lastTrickButton
                }
                scoresheetButton
                if onLeaveTable != nil {
                    leaveButton
                }
                overflowMenu
            }
        }
        .confirmationDialog(
            "Leave this table?",
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button("Leave table", role: .destructive) {
                onLeaveTable?()
            }
            Button("Stay", role: .cancel) {}
        } message: {
            Text("Your current match will be discarded.")
        }
    }

    /// Shared hit-target treatment for the header's icon buttons. The
    /// glyphs render at ~22 pt; without this the tappable area is the
    /// glyph itself (~31 pt), well under the 44 pt HIG minimum. 40 pt is
    /// the compromise that still fits four buttons plus the phase chip on
    /// a compact phone.
    private func headerIconTarget<Glyph: View>(_ glyph: Glyph) -> some View {
        glyph
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
    }

    private var lastTrickButton: some View {
        Button {
            activeSheet = .lastTrick
        } label: {
            headerIconTarget(
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(TableTheme.goldBright, Color.black.opacity(0.30))
                    .font(.title3)
            )
        }
        .accessibilityLabel("Last trick")
        .accessibilityIdentifier(UIIdentifiers.buttonLastTrick)
    }

    /// One-tap exit from the live table. Always reachable so the user is
    /// never trapped — confirms before tearing down the match so a
    /// mistapped exit doesn't lose the deal.
    private var leaveButton: some View {
        Button {
            showLeaveConfirm = true
        } label: {
            headerIconTarget(
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(TableTheme.inkCream, Color.black.opacity(0.30))
                    .font(.title3)
            )
        }
        .accessibilityLabel("Leave table")
        .accessibilityIdentifier(UIIdentifiers.buttonLeaveTable)
    }

    /// Surfaces the scoresheet directly in the header instead of burying it
    /// in the overflow menu — it's the most-wanted info during a match.
    private var scoresheetButton: some View {
        Button {
            activeSheet = .score
        } label: {
            headerIconTarget(
                Image(systemName: "tablecells.fill")
                    .foregroundStyle(TableTheme.inkCream)
                    .font(.subheadline.weight(.semibold))
                    .padding(6)
                    .background(Color.black.opacity(0.30), in: Capsule())
            )
        }
        .accessibilityLabel("Scoresheet")
        .accessibilityIdentifier(UIIdentifiers.buttonScoreSheet)
    }

    private var phaseChip: some View {
        HStack(spacing: 6) {
            Text(Localized.phaseTitle(projection.phase))
                .font(.caption.weight(.bold))
                // Phase name is orientation, not an action — cream, not gold.
                .foregroundStyle(TableTheme.inkCream)
                .lineLimit(1)
                .accessibilityIdentifier(UIIdentifiers.phaseTitle)
            if !shouldShowCenterDealCTA {
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(TableTheme.inkCreamDim)
                Localized.statusText(projection)
                    .font(.caption)
                    .foregroundStyle(TableTheme.inkCreamSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .accessibilityIdentifier(UIIdentifiers.phaseMessage)
            } else {
                // Idle state: the centered Deal CTA already says everything
                // the message would. Keep the AX node so XCUI tests that
                // sample phase.message in idle still find a label, but make
                // it invisible so the chip stays compact.
                Localized.statusText(projection)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(width: 0, height: 0)
                    .clipped()
                    .opacity(0)
                    .accessibilityIdentifier(UIIdentifiers.phaseMessage)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .feltSurface(.chip, radius: TableTheme.Radius.pill)
    }

    private var overflowMenu: some View {
        SwiftUI.Menu {
            extraMenu

            Button {
                activeSheet = .log
            } label: {
                Label("Activity log", systemImage: "scroll")
            }
            Divider()
            Button {
                activeSheet = .settings
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            if onLeaveTable != nil {
                Divider()
                Button(role: .destructive) {
                    showLeaveConfirm = true
                } label: {
                    Label("Leave table", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        } label: {
            headerIconTarget(
                Image(systemName: "ellipsis.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(TableTheme.inkCream, Color.black.opacity(0.30))
                    .font(.title3)
            )
            .accessibilityLabel("Menu")
        }
        .accessibilityIdentifier(UIIdentifiers.overflowMenu)
    }

    // MARK: - Viewer hand

    @ViewBuilder
    private var viewerHandFan: some View {
        if let seat = activeHandSeat {
            let isDiscardPhase = projection.legal.canDiscard
            let canSelectDiscard = isDiscardPhase && !isTalonTakePending
            let playable: Set<Card> = isDiscardPhase ? [] : playableCards(for: seat.player)
            let selected: Set<Card> = isDiscardPhase
                ? (canSelectDiscard ? selectedDiscard : [])
                : selectedCards(for: seat.player)
            let talonKnown: [Card] = canSelectDiscard ? projection.talon.compactMap(\.knownCard) : []
            let cards: [ProjectedCard] = canSelectDiscard
                ? sortedHandFan(seat.hand + projection.talon)
                : sortedHandFan(seat.hand)
            let onCardTap: ((Card) -> Void)? = isTalonTakePending ? nil : { card in
                if isDiscardPhase {
                    toggleDiscardSelection(card)
                } else {
                    selectPlayCard(card)
                }
            }
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    CardFanView(
                        cards: cards,
                        playableCards: playable,
                        selectedCards: selected,
                        talonCards: Set(talonKnown),
                        seat: seat.player,
                        size: horizontalSizeClass == .compact ? .standard : .large,
                        animationNamespace: cardNamespace,
                        onTap: onCardTap,
                        onDoubleTap: isDiscardPhase ? nil : { card in
                            playCard(card, from: seat.player)
                        },
                        onDragEnded: isDiscardPhase ? nil : { card in
                            playCard(card, from: seat.player)
                        }
                    )
                    .shadow(color: seat.isCurrentActor ? TableTheme.goldBright.opacity(0.35) : .clear,
                            radius: seat.isCurrentActor ? 12 : 0)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(UIIdentifiers.seatContainer(seat.player))

                    if seat.isCurrentActor {
                        viewerActorAccessibilityMarker
                    }
                }
                ownerNamePlate(seat: seat)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
        }
    }

    private var viewerActorAccessibilityMarker: some View {
        Text("Acting")
            .frame(width: 0, height: 0)
            .clipped()
            .opacity(0)
            .accessibilityIdentifier(UIIdentifiers.seatCurrentActor(projection.viewer))
    }

    /// Hidden probe re-exposing the viewer-pill contract to UI tests: a
    /// `viewer.label` static text whose accessibility label is
    /// "Viewing as <viewer>", parsed back by `MatchUIRobot.currentViewer()`.
    /// Sourced from `projection.viewer` (not the name-plate's seat) so it
    /// still names the viewer when the bottom fan flips to a controlled
    /// passer during single-whist play. Kept barely-there (1×1, opacity
    /// 0.001) rather than zero-frame or `.accessibilityHidden` — XCUITest
    /// elides fully transparent, zero-size views from its query tree, which
    /// is exactly what orphaned this contract before.
    private var viewerAccessibilityLabel: some View {
        Text(AccessibilityStrings.viewerLabelPrefix + projection.displayName(for: projection.viewer))
            .font(.caption2)
            .frame(width: 1, height: 1)
            .clipped()
            .opacity(0.001)
            .accessibilityIdentifier(UIIdentifiers.viewerLabel)
    }

    private func sortedHandFan(_ cards: [ProjectedCard]) -> [ProjectedCard] {
        cards.sortedForTableDisplay(order: cardSuitDisplayOrder)
    }

    /// Single-row name plate for the viewer's seat. One signal per piece of
    /// info: name (always cream — gold-on-turn was redundant with the
    /// "Your turn" pill below), one inline status pill (Your turn > Dealer
    /// > Sitting out > silent fallback), one persistent role pill
    /// ("Declarer" / "Whist" / "½" / "Pass") so the player can see their
    /// own contract role without scanning the strip, and a quiet trick
    /// counter.
    private func ownerNamePlate(seat: SeatProjection) -> some View {
        HStack(spacing: 8) {
            Text(seat.displayName)
                .font(.caption.bold())
                .foregroundStyle(TableTheme.inkCream)
                .accessibilityIdentifier(UIIdentifiers.scorePlayer(seat.player))
                .accessibilityLabel("Viewing as \(projection.displayName(for: projection.viewer))")
                .accessibilityValue("you")
            viewerAccessibilityLabel
            seatStatusPill(seat: seat)
            if let badge = seatRoleBadges[seat.player] {
                viewerRolePill(badge: badge, player: seat.player)
            }
            if let lastAction = seatActions[seat.player] {
                viewerLastActionPill(action: lastAction)
            }
            Spacer(minLength: 4)
            if seat.trickCount > 0 || isPlayingPhase {
                Text("\(seat.trickCount)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(TableTheme.inkCreamSoft)
                    .accessibilityLabel("\(seat.trickCount) tricks")
                    .accessibilityIdentifier(UIIdentifiers.seatTrickCount(seat.player))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    /// Persistent contract-role pill for the viewer, matching the seat
    /// version on opponents. Sticks for the entire deal once a contract
    /// is on the table.
    private func viewerRolePill(badge: SeatRoleBadge, player: PlayerID) -> some View {
        Text(badge.label)
            .font(.caption2.weight(.bold))
            .tracking(0.3)
            .foregroundStyle(badge.isAccent ? TableTheme.feltDeep : TableTheme.inkCreamSoft)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                // Dim gold (not bright) for the contract role: a second,
                // quieter tier so it reads as identity while bright gold stays
                // reserved for whose-turn and the viewer's live controls.
                Capsule().fill(
                    badge.isAccent
                        ? TableTheme.gold
                        : Color.black.opacity(0.30)
                )
            )
            .accessibilityIdentifier(UIIdentifiers.seatRoleBadge(player))
    }

    /// Inline gold-tinted pill rendering the viewer's most recent
    /// auction-trail action (bid / pass / whist / declared / discarded /
    /// defender mode). Cleared once trick play starts — the role pill
    /// then carries the same information persistently.
    private func viewerLastActionPill(action: RecentAction) -> some View {
        HStack(spacing: 4) {
            action.label.glyph(emphasis: .seat)
                .font(.caption2.weight(.bold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(Capsule().fill(TableTheme.gold.opacity(0.20)))
        .overlay(
            Capsule().strokeBorder(TableTheme.gold.opacity(0.45), lineWidth: 0.5)
        )
        .accessibilityIdentifier(UIIdentifiers.seatLastAction(action.player))
    }

    /// Mutually-exclusive status pill for the viewer's seat. "Your turn"
    /// wins because it's actionable; everything else is informational and
    /// lower-priority. Sitting-out 4-player dealers get the same treatment
    /// as opponent tiles so the user knows the deal will skip them.
    @ViewBuilder
    private func seatStatusPill(seat: SeatProjection) -> some View {
        if seat.isCurrentActor {
            Text("Your turn")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .foregroundStyle(TableTheme.feltDeep)
                .background(TableTheme.goldBright, in: Capsule())
                .accessibilityIdentifier(UIIdentifiers.seatCurrentActor(seat.player))
        } else if seat.role == .sittingOut {
            Text("Sitting out")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .foregroundStyle(TableTheme.inkCreamSoft)
                .background(Color.black.opacity(0.30), in: Capsule())
                .accessibilityIdentifier(UIIdentifiers.seatRole(seat.player))
        } else if seat.isDealer {
            Text("Dealer")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .foregroundStyle(TableTheme.inkCreamSoft)
                .background(Color.black.opacity(0.30), in: Capsule())
                .accessibilityIdentifier(UIIdentifiers.seatDealer(seat.player))
        } else {
            EmptyView()
        }
    }

    /// True during the trick-play phase. Used to surface "0" tricks during
    /// play (so the user can see they haven't won any yet) but suppress it
    /// during bidding/talon where the counter is meaningless.
    private var isPlayingPhase: Bool {
        if case .playing = projection.phase { return true }
        return false
    }

    // MARK: - Sheets

    private var scoreSheet: some View {
        NavigationStack {
            ScrollView {
                ScoreBoardView(score: projection.score, displayName: projection.displayName(for:))
                    .padding()
            }
            .navigationTitle("Scoresheet")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") { activeSheet = nil }
                        .accessibilityIdentifier(UIIdentifiers.buttonDismissSheet)
                }
            }
        }
    }

    private var logSheet: some View {
        ActivityLogSheet(entries: Array(activityEntries.suffix(60))) {
            activeSheet = nil
        }
    }

    private var lastTrickSheet: some View {
        NavigationStack {
            Group {
                if let trick = projection.lastCompletedTrick {
                    LastTrickView(projection: projection, trick: trick)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 20)
                } else {
                    Text("Last trick")
                        .font(.headline)
                        .foregroundStyle(TableTheme.inkCream)
                        .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .feltBackground()
            .navigationTitle("Last trick")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") { activeSheet = nil }
                        .accessibilityIdentifier(UIIdentifiers.buttonDismissSheet)
                }
            }
        }
    }

    // MARK: - Helpers

    private var viewerSeat: SeatProjection? {
        projection.seats.first { $0.player == projection.viewer }
    }

    private func seatOrderNumber(for player: PlayerID) -> Int? {
        projection.players.firstIndex(of: player).map { $0 + 1 }
    }

    /// Seat whose hand belongs in the bottom fan. Controlled passer hands
    /// stay at the passer's table seat so the whister does not appear to
    /// swap identities mid-trick.
    private var activeHandSeat: SeatProjection? {
        return viewerSeat
    }

    private func toggleDiscardSelection(_ card: Card) {
        guard !isTalonTakePending else { return }
        if selectedDiscard.contains(card) {
            selectedDiscard.remove(card)
        } else if selectedDiscard.count < 2 {
            selectedDiscard.insert(card)
        }
    }

    private var isTalonTakePending: Bool {
        projection.legal.canDiscard && talonTakenSequence != projection.sequence
    }

    private func takeTalon() {
        guard projection.legal.canDiscard else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            talonTakenSequence = projection.sequence
            selectedDiscard.removeAll()
        }
    }

    private func reconcileTalonTakeState() {
        guard projection.legal.canDiscard else {
            talonTakenSequence = nil
            return
        }
        if talonTakenSequence != projection.sequence {
            selectedDiscard.removeAll()
        }
    }

    private func reconcileDiscardSelection() {
        guard projection.legal.canDiscard, !isTalonTakePending else {
            selectedDiscard.removeAll()
            return
        }
        let available = Set((viewerSeat?.hand ?? []).compactMap(\.knownCard)
            + projection.talon.compactMap(\.knownCard))
        selectedDiscard.formIntersection(available)
    }

    private var playableOwner: PlayerID {
        projection.legal.playableCardsOwner ?? projection.viewer
    }

    private func playableCards(for player: PlayerID) -> Set<Card> {
        guard playableOwner == player else { return [] }
        return Set(projection.legal.playableCards)
    }

    private func selectedCards(for player: PlayerID) -> Set<Card> {
        guard playableOwner == player, let selectedPlayCard else { return [] }
        return [selectedPlayCard]
    }

    private func cardSelectHandler(for player: PlayerID) -> ((Card) -> Void)? {
        guard !playableCards(for: player).isEmpty else { return nil }
        return { card in selectPlayCard(card) }
    }

    private func cardPlayHandler(for player: PlayerID) -> ((Card) -> Void)? {
        guard !playableCards(for: player).isEmpty else { return nil }
        return { card in playCard(card, from: player) }
    }

    private func selectPlayCard(_ card: Card) {
        selectedPlayCard = card
    }

    private func playCard(_ card: Card, from owner: PlayerID) {
        guard playableCards(for: owner).contains(card) else {
            selectedPlayCard = card
            return
        }
        selectedPlayCard = nil
        onSend(.playCard(player: owner, card: card))
    }

    private func reconcilePlaySelection() {
        guard let selectedPlayCard else { return }
        let visiblePlayable = Set(projection.legal.playableCards)
        if !visiblePlayable.contains(selectedPlayCard) {
            self.selectedPlayCard = nil
        }
    }
}

private struct ActivityLogSheet: View {
    var entries: [ActivityLogEntry]
    var onDone: () -> Void

    private var newestFirst: [ActivityLogEntry] {
        Array(entries.reversed())
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ActivityLogEmptyState()
                } else {
                    List {
                        Section {
                            ForEach(newestFirst) { entry in
                                ActivityLogRow(entry: entry)
                                    .listRowInsets(.init(top: 6, leading: 14, bottom: 6, trailing: 14))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .accessibilityIdentifier(UIIdentifiers.eventLogEntry(index: entry.id))
                            }
                        } header: {
                            Text("Latest activity")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(TableTheme.inkCreamSoft)
                                .textCase(.uppercase)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.defaultMinListRowHeight, 1)
                }
            }
            .background {
                TableTheme.feltGradient
                    .ignoresSafeArea()
            }
            .navigationTitle("Activity log")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") { onDone() }
                        .accessibilityIdentifier(UIIdentifiers.buttonDismissSheet)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(UIIdentifiers.Panel.eventLog.rawValue)
        }
    }
}

private struct ActivityLogRow: View {
    var entry: ActivityLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(entry.kind.tint.opacity(0.18))
                Image(systemName: entry.kind.iconName)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(entry.kind.tint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: entry.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(TableTheme.inkCream)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = entry.detail {
                    Text(verbatim: detail)
                        .font(.caption)
                        .foregroundStyle(TableTheme.inkCreamSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(verbatim: entry.kind.label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(entry.kind.tint)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(entry.kind.tint.opacity(0.13), in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .feltSurface(.chip, radius: TableTheme.Radius.xs)
        .accessibilityElement(children: .combine)
    }
}

private struct ActivityLogEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "scroll")
                .font(.title2.weight(.semibold))
                .foregroundStyle(TableTheme.goldBright)
                .frame(width: 48, height: 48)
                .background(TableTheme.gold.opacity(0.14), in: Circle())
            Text("No activity yet")
                .font(.headline.weight(.semibold))
                .foregroundStyle(TableTheme.inkCream)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension ActivityLogEntry.Kind {
    var iconName: String {
        switch self {
        case .deal:       return "rectangle.stack.fill"
        case .auction:    return "hand.raised.fill"
        case .contract:   return "checkmark.seal.fill"
        case .defense:    return "shield.fill"
        case .play:       return "suit.club.fill"
        case .settlement: return "text.bubble.fill"
        case .scoring:    return "chart.bar.fill"
        }
    }

    var tint: Color {
        switch self {
        case .deal:       return TableTheme.inkCreamSoft
        case .auction:    return TableTheme.goldBright
        case .contract:   return Color(red: 0.58, green: 0.82, blue: 0.96)
        case .defense:    return Color(red: 0.72, green: 0.86, blue: 0.62)
        case .play:       return Color(red: 0.96, green: 0.78, blue: 0.54)
        case .settlement: return Color(red: 0.84, green: 0.72, blue: 0.96)
        case .scoring:    return TableTheme.gold
        }
    }
}

private struct LastTrickView: View {
    var projection: PlayerGameProjection
    var trick: Trick

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("\(projection.displayName(for: trick.winner)) won")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(TableTheme.goldBright)
                    .multilineTextAlignment(.center)
                Text("Last trick")
                    .font(.caption.weight(.bold))
                    .tracking(1.1)
                    .textCase(.uppercase)
                    .foregroundStyle(TableTheme.inkCreamSoft)
            }
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(Array(trick.plays.enumerated()), id: \.offset) { _, play in
                    trickPlayColumn(play)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .feltSurface(.card, radius: TableTheme.Radius.md)
    }

    private func trickPlayColumn(_ play: CardPlay) -> some View {
        let isWinner = play.player == trick.winner
        return VStack(spacing: 8) {
            CardView(
                card: .known(play.card),
                size: .standard,
                region: .trick(seat: play.player)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isWinner ? TableTheme.goldBright.opacity(0.95) : .clear,
                                  lineWidth: isWinner ? 2 : 0)
            )
            .shadow(color: isWinner ? TableTheme.goldBright.opacity(0.45) : .clear,
                    radius: isWinner ? 12 : 0)
            Text(projection.displayName(for: play.player))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isWinner ? TableTheme.goldBright : TableTheme.inkCreamSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
    }
}
