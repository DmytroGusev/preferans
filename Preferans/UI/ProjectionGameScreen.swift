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
    public var onSend: (PreferansAction) -> Void
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
        case score, log, settings
        var id: String { rawValue }
    }

    @State private var selectedDiscard: Set<Card> = []
    @State private var activeSheet: Sheet?
    @State private var showLeaveConfirm = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Namespace private var cardNamespace

    public init(
        projection: PlayerGameProjection,
        eventLog: [String] = [],
        recentEvents: [PreferansEvent] = [],
        onSend: @escaping (PreferansAction) -> Void,
        onLeaveTable: (() -> Void)? = nil,
        onRematch: (() -> Void)? = nil,
        @ViewBuilder extraMenu: () -> Menu = { EmptyView() }
    ) {
        self.projection = projection
        self.eventLog = eventLog
        self.recentEvents = recentEvents
        self.onSend = onSend
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
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .score:    scoreSheet
            case .log:      logSheet
            case .settings: SettingsScreen()
            }
        }
        .onChange(of: projection.sequence) { _, _ in
            // Game-over rendering is now inline on the felt — see
            // `TableView.gameOverCard`. No modal auto-presentation here.
            reconcileDiscardSelection()
        }
    }

    // MARK: - Compact (iPhone)

    private var compactBody: some View {
        VStack(spacing: 0) {
            headerStrip
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 8)
            TableView(
                projection: projection,
                animationNamespace: cardNamespace,
                onAdvance: advanceToNextDeal,
                onStartDeal: shouldShowCenterDealCTA ? advanceToNextDeal : nil,
                onLeaveTable: onLeaveTable,
                onRematch: onRematch,
                seatActions: seatActions,
                bannerAction: bannerAction
            )
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if shouldShowActionBar {
                ActionBarView(projection: projection, selectedDiscard: selectedDiscard, onSend: onSend)
            }
            if shouldShowHandRail {
                viewerHandFan
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 4)
                    .layoutPriority(1)
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
                    .frame(width: 180)
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
                    lastAction: seatActions[seat.player]
                )
            }
            Spacer(minLength: 0)
        }
    }

    /// Trick area only — no opponent row (the column on the left owns
    /// that). Reuses the same TableView play-area branch as portrait.
    @ViewBuilder
    private var landscapeTablePlayArea: some View {
        TableView(
            projection: projection,
            animationNamespace: cardNamespace,
            onAdvance: advanceToNextDeal,
            onStartDeal: shouldShowCenterDealCTA ? advanceToNextDeal : nil,
            onLeaveTable: onLeaveTable,
            onRematch: onRematch,
            renderOpponentsAtTop: false,
            seatActions: seatActions,
            bannerAction: bannerAction
        )
    }

    private var orderedOpponentSeats: [SeatProjection] {
        projection.seats.filter { $0.player != projection.viewer }
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
                TableView(
                    projection: projection,
                    animationNamespace: cardNamespace,
                    onAdvance: advanceToNextDeal,
                    onStartDeal: shouldShowCenterDealCTA ? advanceToNextDeal : nil,
                    onLeaveTable: onLeaveTable,
                    onRematch: onRematch,
                    seatActions: seatActions,
                    bannerAction: bannerAction
                )
                .frame(maxHeight: .infinity)
                if shouldShowActionBar {
                    ActionBarView(projection: projection, selectedDiscard: selectedDiscard, onSend: onSend)
                }
                if shouldShowHandRail {
                    viewerHandFan
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            ScoreBoardView(score: projection.score)
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
            scoresheetButton
            if onLeaveTable != nil {
                leaveButton
            }
            overflowMenu
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

    /// One-tap exit from the live table. Always reachable so the user is
    /// never trapped — confirms before tearing down the match so a
    /// mistapped exit doesn't lose the deal.
    private var leaveButton: some View {
        Button {
            showLeaveConfirm = true
        } label: {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(TableTheme.inkCream, Color.black.opacity(0.30))
                .font(.title3)
                .padding(4)
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
            Image(systemName: "list.number")
                .foregroundStyle(TableTheme.inkCream)
                .font(.subheadline.weight(.semibold))
                .padding(6)
                .background(Color.black.opacity(0.30), in: Capsule())
        }
        .accessibilityLabel("Scoresheet")
        .accessibilityIdentifier(UIIdentifiers.buttonScoreSheet)
    }

    private var phaseChip: some View {
        HStack(spacing: 6) {
            Text(Localized.phaseTitle(projection.phase))
                .font(.caption.weight(.bold))
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
                Label("Event log", systemImage: "scroll")
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
            Image(systemName: "ellipsis.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(TableTheme.inkCream, Color.black.opacity(0.30))
                .font(.title3)
                .padding(4)
                .accessibilityLabel("Menu")
        }
        .accessibilityIdentifier(UIIdentifiers.overflowMenu)
    }

    // MARK: - Viewer hand

    @ViewBuilder
    private var viewerHandFan: some View {
        if let seat = viewerSeat {
            let isDiscardPhase = projection.legal.canDiscard
            let playable: Set<Card> = isDiscardPhase ? [] : Set(projection.legal.playableCards)
            let selected: Set<Card> = isDiscardPhase ? selectedDiscard : []
            let talonKnown: [Card] = isDiscardPhase ? projection.talon.compactMap(\.knownCard) : []
            let cards: [ProjectedCard] = isDiscardPhase
                ? sortedHandFan(seat.hand + projection.talon)
                : seat.hand
            VStack(spacing: 4) {
                CardFanView(
                    cards: cards,
                    playableCards: playable,
                    selectedCards: selected,
                    talonCards: Set(talonKnown),
                    seat: seat.player,
                    size: horizontalSizeClass == .compact ? .standard : .large,
                    animationNamespace: cardNamespace,
                    onTap: { card in
                        if isDiscardPhase {
                            toggleDiscardSelection(card)
                        } else if playable.contains(card) {
                            onSend(.playCard(player: projection.viewer, card: card))
                        }
                    }
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(UIIdentifiers.seatContainer(seat.player))
                ownerNamePlate(seat: seat)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
        }
    }

    private func sortedHandFan(_ cards: [ProjectedCard]) -> [ProjectedCard] {
        cards.sorted { lhs, rhs in
            switch (lhs.knownCard, rhs.knownCard) {
            case let (l?, r?): return l < r
            case (_, nil):     return true
            case (nil, _):     return false
            }
        }
    }

    /// Single-row name plate for the viewer's seat. One signal per piece of
    /// info: name (always cream — gold-on-turn was redundant with the
    /// "Your turn" pill below), one inline pill (Your turn > Dealer >
    /// Sitting out > silent fallback), and a quiet trick counter. The
    /// previous version stacked a hand-icon, gold name, "you" pill, dot,
    /// "X tricks" label, "Dealer" pill, and "Your turn" pill in one row —
    /// seven signals for two pieces of state.
    private func ownerNamePlate(seat: SeatProjection) -> some View {
        HStack(spacing: 8) {
            Text(seat.displayName)
                .font(.caption.bold())
                .foregroundStyle(TableTheme.inkCream)
                .accessibilityIdentifier(UIIdentifiers.scorePlayer(seat.player))
                .accessibilityLabel("Viewing as \(projection.displayName(for: projection.viewer))")
                .accessibilityValue("you")
            Text("you")
                .font(.caption2.bold())
                .padding(.horizontal, 0)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
                .accessibilityIdentifier(UIIdentifiers.viewerLabel)
            seatStatusPill(seat: seat)
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

    /// Inline gold-tinted pill rendering the viewer's most recent action,
    /// matching the per-seat badge on opponents. Lets the player see at a
    /// glance what they last did without having to mentally replay the
    /// auction trail.
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
                ScoreBoardView(score: projection.score)
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
        let recent = Array(eventLog.suffix(40))
        return NavigationStack {
            List {
                Section("Recent events") {
                    ForEach(recent.indices.reversed(), id: \.self) { index in
                        Text(recent[index])
                            .font(.caption.monospaced())
                            .accessibilityIdentifier(UIIdentifiers.eventLogEntry(index: index))
                    }
                }
            }
            .navigationTitle("Event log")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") { activeSheet = nil }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(UIIdentifiers.Panel.eventLog.rawValue)
        }
    }

    // MARK: - Helpers

    private var viewerSeat: SeatProjection? {
        projection.seats.first { $0.player == projection.viewer }
    }

    private func toggleDiscardSelection(_ card: Card) {
        if selectedDiscard.contains(card) {
            selectedDiscard.remove(card)
        } else if selectedDiscard.count < 2 {
            selectedDiscard.insert(card)
        }
    }

    private func reconcileDiscardSelection() {
        guard projection.legal.canDiscard else {
            selectedDiscard.removeAll()
            return
        }
        let available = Set((viewerSeat?.hand ?? []).compactMap(\.knownCard)
            + projection.talon.compactMap(\.knownCard))
        selectedDiscard.formIntersection(available)
    }
}
