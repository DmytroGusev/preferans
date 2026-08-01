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
    /// Recent strategic notes from local bot seats. Online callers omit this
    /// presentation-only stream until the protocol transports an equivalent
    /// public-safe note explicitly.
    public var botInsights: [BotDecisionExplanation]
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
    let extraMenu: Menu
    private let seatActions: [PlayerID: RecentAction]
    private let bannerAction: RecentAction?
    private let seatRoleBadges: [PlayerID: SeatRoleBadge]

    @State private var selectedDiscard: Set<Card> = []
    @State private var selectedPlayCard: Card?
    @State private var talonTakenSequence: Int?
    @State var activeSheet: GameSheetDestination?
    @State var showLeaveConfirm = false
    @AppStorage(SettingsKeys.cardSuitDisplayOrder) private var cardSuitDisplayOrderRaw: String = CardSuitDisplayOrder.default.rawValue
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Namespace private var cardNamespace

    public init(
        projection: PlayerGameProjection,
        eventLog: [String] = [],
        recentEvents: [PreferansEvent] = [],
        botInsights: [BotDecisionExplanation] = [],
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
        self.botInsights = botInsights
        self.pendingAdvance = pendingAdvance
        self.idleHintActive = idleHintActive
        self.onSend = onSend
        self.onTapToAdvance = onTapToAdvance
        self.onLeaveTable = onLeaveTable
        self.onRematch = onRematch
        self.extraMenu = extraMenu()
        // Stored, not computed: both derive by scanning the recent-event ring
        // buffer (up to 120 entries), and body reads them once per seat. As
        // computed properties that scan re-ran on every access; here it runs
        // once per view construction.
        self.seatActions = RecentActionFeed.perSeat(from: recentEvents)
        self.bannerAction = RecentActionFeed.banner(from: recentEvents)
        self.seatRoleBadges = SeatRoleBadgeFeed.perSeat(from: projection)
    }

    private var activityEntries: [ActivityLogEntry] {
        ActivityLogFeed.entries(from: recentEvents, displayName: projection.displayName(for:))
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
            GameDetailSheet(
                destination: sheet,
                projection: projection,
                activityEntries: Array(activityEntries.suffix(60)),
                botInsights: botInsights
            ) {
                activeSheet = nil
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
            tableView()
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
                actionBar()
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
                        actionBar()
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
    /// varies.
    private func tableView(renderOpponentsAtTop: Bool = true) -> TableView {
        // The method reference `advanceToNextDeal` trips a Swift 6
        // type-checker bug here ("failed to produce diagnostic for
        // expression"); wrapping in an explicit closure sidesteps it
        // and is equivalent at the call site.
        let advance: () -> Void = { advanceToNextDeal() }
        return TableView(
            projection: projection,
            animationNamespace: cardNamespace,
            handlers: TableHandlers(
                onAdvance: advance,
                onStartDeal: shouldShowCenterDealCTA ? advance : nil,
                onLeaveTable: onLeaveTable,
                onRematch: onRematch,
                onSelectPlayCard: selectPlayCard,
                onPlayCard: { owner, card in playCard(card, from: owner) },
                onTakeTalon: takeTalon,
                onTapToAdvance: onTapToAdvance
            ),
            display: TableDisplayState(
                renderOpponentsAtTop: renderOpponentsAtTop,
                idleHintActive: idleHintActive,
                isTalonTakePending: isTalonTakePending
            ),
            seatActions: seatActions,
            seatRoleBadges: seatRoleBadges,
            bannerAction: bannerAction,
            botInsight: botInsights.last,
            pendingAdvance: pendingAdvance,
            cardSuitOrder: cardSuitDisplayOrder,
            selectedPlayCard: selectedPlayCard
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
        GeometryReader { geometry in
            let split = TableLayoutModel.RegularSplit(totalWidth: geometry.size.width)
            HStack(alignment: .top, spacing: split.spacing) {
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
                        actionBar(availableChoiceWidth: max(0, split.tableWidth - 24))
                    }
                }
                .frame(width: split.tableWidth)
                ScrollView {
                    ScoreBoardView(
                        score: projection.score,
                        rules: projection.rules,
                        presentation: .feltSidebar,
                        displayName: projection.displayName(for:)
                    )
                }
                    .scrollIndicators(.hidden)
                    .frame(width: split.sidebarWidth)
            }
            .padding(.vertical, 16)
            .padding(.trailing, split.trailingInset)
        }
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
    var shouldShowCenterDealCTA: Bool {
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
        return ActionBarLayoutPolicy.shouldShow(
            legal: projection.legal,
            hasSelectedPlayCard: selectedPlayCard != nil,
            horizontalSizeClass: horizontalSizeClass
        )
    }

    private func actionBar(availableChoiceWidth: CGFloat? = nil) -> some View {
        ActionBarView(
            projection: projection,
            selectedDiscard: selectedDiscard,
            selectedPlayCard: selectedPlayCard,
            onSend: onSend,
            onPlaySelected: playSelectedCard,
            availableChoiceWidth: availableChoiceWidth
        )
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
            if let seatOrder = seatOrderNumber(for: seat.player) {
                SeatOrderBadge(
                    number: seatOrder,
                    player: seat.player,
                    isCurrentActor: seat.isCurrentActor
                )
            }
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

    private func playSelectedCard() {
        guard let selectedPlayCard else { return }
        playCard(selectedPlayCard, from: playableOwner)
    }

    private func reconcilePlaySelection() {
        guard let selectedPlayCard else { return }
        let visiblePlayable = Set(projection.legal.playableCards)
        if !visiblePlayable.contains(selectedPlayCard) {
            self.selectedPlayCard = nil
        }
    }
}

/// Compact tables already name the current actor in the header and mark the
/// viewer's hand when it is playable. Keep the bottom surface only when it
/// contains a real control; regular-width tables retain the persistent status
/// lane because it does not compete with the play area for vertical space.
enum ActionBarLayoutPolicy {
    static func shouldShow(
        legal: LegalActionProjection,
        hasSelectedPlayCard: Bool = false,
        horizontalSizeClass: UserInterfaceSizeClass?
    ) -> Bool {
        guard horizontalSizeClass == .compact else { return true }
        return hasSelectedPlayCard
            || !legal.bidCalls.isEmpty
            || !legal.contractOptions.isEmpty
            || !legal.whistCalls.isEmpty
            || !legal.defenderModes.isEmpty
            || legal.canDiscard
            || !legal.settlementOptions.isEmpty
            || legal.pendingSettlement != nil
            || legal.canAcceptSettlement
            || legal.canRejectSettlement
    }
}
