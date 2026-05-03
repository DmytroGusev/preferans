import SwiftUI
import PreferansEngine

public struct ProjectionGameScreen<Menu: View>: View {
    public var projection: PlayerGameProjection
    public var eventLog: [String]
    public var onSend: (PreferansAction) -> Void
    private let extraMenu: Menu

    private enum Sheet: String, Identifiable {
        case score, log, settings
        var id: String { rawValue }
    }

    @State private var selectedDiscard: Set<Card> = []
    @State private var activeSheet: Sheet?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Namespace private var cardNamespace

    public init(
        projection: PlayerGameProjection,
        eventLog: [String] = [],
        onSend: @escaping (PreferansAction) -> Void,
        @ViewBuilder extraMenu: () -> Menu = { EmptyView() }
    ) {
        self.projection = projection
        self.eventLog = eventLog
        self.onSend = onSend
        self.extraMenu = extraMenu()
    }

    public var body: some View {
        Group {
            if horizontalSizeClass == .compact {
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
                onStartDeal: shouldShowCenterDealCTA ? advanceToNextDeal : nil
            )
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if shouldShowActionBar {
                ActionBarView(projection: projection, selectedDiscard: selectedDiscard, onSend: onSend)
            }
            viewerHandFan
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 4)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .feltBackground()
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
                    onStartDeal: shouldShowCenterDealCTA ? advanceToNextDeal : nil
                )
                .frame(maxHeight: .infinity)
                if shouldShowActionBar {
                    ActionBarView(projection: projection, selectedDiscard: selectedDiscard, onSend: onSend)
                }
                viewerHandFan
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
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
            overflowMenu
        }
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
            Button {
                activeSheet = .score
            } label: {
                Label("Scoresheet", systemImage: "list.number")
            }
            .accessibilityIdentifier(UIIdentifiers.buttonScoreSheet)

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
            .background(handRail)
        }
    }

    /// "Card rest" rail behind the viewer's hand. Slightly darker than the
    /// felt with a hairline gold edge up top so the cards have a clear
    /// shelf to sit on instead of floating against the felt.
    private var handRail: some View {
        LinearGradient(
            colors: [Color.black.opacity(0.28), Color.black.opacity(0.16)],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(TableTheme.gold.opacity(0.22))
                .frame(height: 0.5)
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

    private func ownerNamePlate(seat: SeatProjection) -> some View {
        HStack(spacing: 6) {
            if seat.isCurrentActor {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.caption2)
                    .foregroundStyle(TableTheme.goldBright)
            }
            Text(seat.displayName)
                .font(.caption.bold())
                .foregroundStyle(seat.isCurrentActor ? TableTheme.goldBright : TableTheme.inkCream)
                .accessibilityIdentifier(UIIdentifiers.scorePlayer(seat.player))
            // The "you" pill replaces the old "you: <name>" line in the
            // status bar. The accessibility label renders "Viewing as <name>"
            // for MatchUIRobot.currentViewer().
            Text("you")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .foregroundStyle(TableTheme.inkCream)
                .background(Color.black.opacity(0.30), in: Capsule())
                .accessibilityLabel("Viewing as \(projection.displayName(for: projection.viewer))")
                .accessibilityIdentifier(UIIdentifiers.viewerLabel)
            if seat.isDealer {
                Text("Dealer")
                    .font(.caption2)
                    .foregroundStyle(TableTheme.inkCreamSoft)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.30), in: Capsule())
                    .accessibilityIdentifier(UIIdentifiers.seatDealer(seat.player))
            }
            if seat.isCurrentActor {
                Text("Your turn")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .foregroundStyle(TableTheme.feltDeep)
                    .background(TableTheme.goldBright, in: Capsule())
                    .accessibilityIdentifier(UIIdentifiers.seatCurrentActor(seat.player))
            }
            Spacer()
            Text("\(seat.trickCount) tricks")
                .font(.caption2)
                .foregroundStyle(TableTheme.inkCreamSoft)
                .accessibilityIdentifier(UIIdentifiers.seatTrickCount(seat.player))
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
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
