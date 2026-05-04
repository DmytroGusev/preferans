import SwiftUI
import PreferansEngine

/// The central play area. Each opponent has a fixed slot above the felt;
/// the viewer's slot is at the bottom. The current trick cards land on
/// their owner's slot. During talon exchange the talon sits in the
/// middle of the felt for the declarer to pick from.
public struct TableView: View {
    public var projection: PlayerGameProjection
    public var animationNamespace: Namespace.ID
    /// Tap handler for the deal-summary card's "Next deal" button.
    public var onAdvance: (() -> Void)?
    /// Tap handler for the centered Deal CTA shown on the empty felt
    /// during the pre-first-deal idle state. When `nil`, the centered CTA
    /// is suppressed and the felt falls back to the phase placeholder.
    public var onStartDeal: (() -> Void)?
    /// "Back to lobby" CTA on the game-over card.
    public var onLeaveTable: (() -> Void)?
    /// "Rematch" CTA on the game-over card.
    public var onRematch: (() -> Void)?
    /// When false, the top opponent row + DealStateStrip are suppressed —
    /// the landscape layout owns those externally. Only the play area is
    /// rendered. Defaults to true (portrait layout).
    public var renderOpponentsAtTop: Bool
    /// Per-seat latest auction-trail action, used to render an inline pill
    /// on each opponent's name chip during bidding/discard/whist phases.
    /// The screen above us derives the dictionary from the engine event
    /// stream so this view only reads it. Cleared once trick play starts —
    /// the persistent role badge takes over from then on.
    public var seatActions: [PlayerID: RecentAction]
    /// Per-seat persistent contract-role pill ("Declarer" / "Whist" / "½"
    /// / "Pass"). Pre-computed by the screen above us from the projection
    /// so each subview only renders.
    public var seatRoleBadges: [PlayerID: SeatRoleBadge]
    /// The most recent banner-worthy action across the whole table. Drives
    /// the centered toast that fades out after a short hold.
    public var bannerAction: RecentAction?
    /// When non-nil, the felt is paused on a beat the human just observed
    /// (their card landing, a bot's reply, a completed trick). The table
    /// renders a "tap to continue" overlay and any tap on the felt fires
    /// `onTapToAdvance`. Hand and overflow-menu interactions remain live
    /// underneath.
    public var pendingAdvance: PendingAdvance?
    /// True once the pause has been up long enough that the table should
    /// escalate the hint into a more prominent "Waiting for you" pulse.
    public var idleHintActive: Bool
    /// Called when the felt is tapped during a tap-to-advance pause.
    public var onTapToAdvance: (() -> Void)?
    @State private var showInitialHands = false

    public init(
        projection: PlayerGameProjection,
        animationNamespace: Namespace.ID,
        onAdvance: (() -> Void)? = nil,
        onStartDeal: (() -> Void)? = nil,
        onLeaveTable: (() -> Void)? = nil,
        onRematch: (() -> Void)? = nil,
        renderOpponentsAtTop: Bool = true,
        seatActions: [PlayerID: RecentAction] = [:],
        seatRoleBadges: [PlayerID: SeatRoleBadge] = [:],
        bannerAction: RecentAction? = nil,
        pendingAdvance: PendingAdvance? = nil,
        idleHintActive: Bool = false,
        onTapToAdvance: (() -> Void)? = nil
    ) {
        self.projection = projection
        self.animationNamespace = animationNamespace
        self.onAdvance = onAdvance
        self.onStartDeal = onStartDeal
        self.onLeaveTable = onLeaveTable
        self.onRematch = onRematch
        self.renderOpponentsAtTop = renderOpponentsAtTop
        self.seatActions = seatActions
        self.seatRoleBadges = seatRoleBadges
        self.bannerAction = bannerAction
        self.pendingAdvance = pendingAdvance
        self.idleHintActive = idleHintActive
        self.onTapToAdvance = onTapToAdvance
    }

    public var body: some View {
        let opponents = orderedOpponents()
        let active = opponents.filter { $0.role != .sittingOut }
        let sittingOut = opponents.filter { $0.role == .sittingOut }
        Group {
            if renderOpponentsAtTop {
                VStack(spacing: 4) {
                    DealStateStrip(projection: projection)
                    tableLayout(active: active, sittingOut: sittingOut)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                playArea(opponentSeats: active.map(\.player))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 200)
            }
        }
        .overlay { tapToAdvanceOverlay }
    }

    /// Felt-wide tap target shown while the table is paused between card-play beats.
    @ViewBuilder
    private var tapToAdvanceOverlay: some View {
        if let advance = pendingAdvance, let onTap = onTapToAdvance {
            ZStack {
                Color.black.opacity(idleHintActive ? 0.18 : 0.05)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap() }
                tapToAdvanceHint(advance: advance)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(UIIdentifiers.tapToAdvance)
            .transition(.opacity)
        }
    }

    private func tapToAdvanceHint(advance: PendingAdvance) -> some View {
        let waitingName = projection.displayName(for: advance.waitingOn)
        return VStack(spacing: 4) {
            if idleHintActive {
                Text("Waiting for \(waitingName)")
                    .font(.headline.bold())
                    .foregroundStyle(TableTheme.goldBright)
                    .accessibilityIdentifier(UIIdentifiers.waitingForViewer)
            }
            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.caption)
                Text("Tap to continue")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(TableTheme.inkCream)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, idleHintActive ? 10 : 7)
        .background(
            Capsule().fill(Color.black.opacity(idleHintActive ? 0.75 : 0.55))
        )
        .overlay(
            Capsule().strokeBorder(
                idleHintActive ? TableTheme.goldBright.opacity(0.7) : TableTheme.inkCream.opacity(0.15),
                lineWidth: idleHintActive ? 1.2 : 0.5
            )
        )
        .scaleEffect(idleHintActive ? 1.06 : 1.0)
        .shadow(color: idleHintActive ? TableTheme.goldBright.opacity(0.45) : .black.opacity(0.25),
                radius: idleHintActive ? 14 : 4)
        .animation(.easeInOut(duration: 0.35), value: idleHintActive)
    }

    /// Real card-table layout: opponents are positioned around the felt
    /// (top, left, right) at their seat slots — not stacked
    /// shoulder-to-shoulder at the top. The trick area sits in the center
    /// and grows to fill the available real estate. The 4-player
    /// sitting-out dealer is excluded from the main slot layout so that
    /// active opponents claim the full upper third instead of sharing it
    /// with a player who isn't dealing in this hand; the sitting-out seat
    /// collapses to a small corner chip so the user still sees who's at
    /// the table.
    private func tableLayout(active: [SeatProjection], sittingOut: [SeatProjection]) -> some View {
        GeometryReader { geo in
            let layout = TableLayoutModel(bounds: geo.size)
            let bounds = layout.bounds
            ZStack(alignment: .topTrailing) {
                // Center: trick area / phase content. Sized smaller than
                // the felt so seat fans can sit at the edges without
                // overlapping it.
                // Center the play area in the open felt below the
                // opponent row. Every opponent slot now lives in the
                // upper third (y ≤ ~0.30) so the trick area can claim
                // the lower two-thirds and stay optically centered for
                // every seat configuration.
                playArea(opponentSeats: active.map(\.player))
                    .frame(width: layout.playAreaSize.width,
                           height: layout.playAreaSize.height)
                    .position(layout.playAreaPosition)

                // Active opponent seats positioned around the felt edge.
                ForEach(Array(layout.opponentSlots(opponents: active).enumerated()), id: \.offset) { _, slot in
                    let slotSize = layout.slotFrameSize(for: slot)
                    OpponentSeatView(
                        seat: slot.seat,
                        orientation: slot.orientation,
                        lastAction: seatActions[slot.seat.player],
                        roleBadge: seatRoleBadges[slot.seat.player]
                    )
                    .frame(width: slotSize.width,
                           height: slotSize.height)
                    .position(x: slot.position.x * bounds.width,
                              y: slot.position.y * bounds.height)
                }

                // Centered action banner (transient toast). Sits above the
                // play area but ignores hit testing so it never blocks
                // taps on the trick or the deal-summary CTA.
                CenterActionBanner(
                    action: bannerAction,
                    displayName: { projection.displayName(for: $0) }
                )
                .position(layout.bannerPosition)

                // Sitting-out dealer(s) tucked into the top-right corner
                // as compact chips so they don't claim a full opponent
                // slot. The chip itself is rendered by OpponentSeatView's
                // sitting-out branch.
                if !sittingOut.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        ForEach(sittingOut) { seat in
                            OpponentSeatView(
                                seat: seat,
                                orientation: .top,
                                lastAction: nil,
                                roleBadge: nil
                            )
                        }
                    }
                    .padding(.top, 4)
                    .padding(.trailing, 6)
                }
            }
            .frame(width: bounds.width, height: bounds.height)
        }
        .frame(minHeight: 320)
    }

    /// The center of the felt where the current trick sits. The felt is the
    /// screen background; this view only places the trick / phase-message
    /// content into the open middle. Public talon cards live on the center
    /// felt so every seat sees the same table information.
    @ViewBuilder
    private func playArea(opponentSeats: [PlayerID]) -> some View {
        if case let .gameOver(summary) = projection.phase {
            GameOverCard(summary: summary, onRematch: onRematch, onLeaveTable: onLeaveTable)
        } else if case let .dealFinished(result) = projection.phase {
            dealSummaryCard(result: result)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(UIIdentifiers.Panel.dealFinished.rawValue)
        } else if let onStartDeal, projection.legal.canStartDeal {
            // Idle pre-first-deal: the felt's *only* affordance is the Deal
            // CTA, centered. The action bar at the bottom is suppressed
            // while this is up so we never present two buttons that mean
            // the same thing.
            startDealCenter(onStartDeal: onStartDeal)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(UIIdentifiers.Panel.currentTrick.rawValue)
        } else {
            ZStack {
                if projection.currentTrick.isEmpty {
                    phaseContext()
                } else {
                    trickPlays(opponentSeats: opponentSeats)
                    if shouldShowPublicTalon {
                        talonContext(title: "Talon", size: .compact)
                            .offset(y: -96)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(UIIdentifiers.Panel.currentTrick.rawValue)
        }
    }

    /// Phase-aware center-felt content. The DealStateStrip above the play
    /// area already surfaces auction state, contract, whisters, and
    /// vzyatki, so the center is reserved for things that need real
    /// estate: the talon during exchange, played cards during play, or a
    /// quiet "waiting on …" line when nothing is on the felt yet.
    @ViewBuilder
    private func phaseContext() -> some View {
        switch projection.phase {
        case .awaitingDiscard:
            talonContext()
        case .playing(_, _, kind: .allPass) where shouldShowPublicTalon:
            talonContext(title: "Talon")
        case .bidding, .awaitingContract:
            biddingContext()
        default:
            EmptyView()
        }
    }

    /// Bidding-phase center cluster. One pill per active seat showing
    /// the latest call (bid / pass) or a quiet "…" while the seat is
    /// still pending. The current caller's pill is ringed in gold so
    /// the eye lands on whose turn it is. Replaces the small
    /// auction-trail row at the top of the strip as the primary read
    /// of "where is the auction".
    private func biddingContext() -> some View {
        let active = projection.seats.filter { $0.role != .sittingOut }
        return VStack(spacing: 14) {
            auctionPanelTitle
            HStack(spacing: 0) {
                ForEach(Array(active.enumerated()), id: \.element.player) { index, seat in
                    auctionSeatPill(seat: seat)
                        .frame(maxWidth: .infinity)
                    if index < active.count - 1 {
                        Rectangle()
                            .fill(TableTheme.gold.opacity(0.22))
                            .frame(width: 0.5, height: 70)
                            .padding(.horizontal, 8)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: TableTheme.Radius.md, style: .continuous)
                .fill(Color.black.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: TableTheme.Radius.md, style: .continuous)
                .strokeBorder(TableTheme.gold.opacity(0.34), lineWidth: 0.75)
        )
        .multilineTextAlignment(.center)
    }

    private var auctionPanelTitle: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(TableTheme.gold.opacity(0.38))
                .frame(height: 0.6)
            Text("Auction")
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(TableTheme.goldBright)
                .fixedSize()
            Rectangle()
                .fill(TableTheme.gold.opacity(0.38))
                .frame(height: 0.6)
        }
    }

    private func auctionSeatPill(seat: SeatProjection) -> some View {
        let action = seatActions[seat.player]
        let isCurrent = seat.isCurrentActor
        return VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(seat.player == projection.viewer ? TableTheme.goldBright : TableTheme.inkCreamSoft)
                    .accessibilityHidden(true)
                Text(seat.player == projection.viewer ? "You" : seat.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(seat.player == projection.viewer ? TableTheme.inkCream : TableTheme.inkCreamSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Group {
                if let action {
                    action.label.glyph(emphasis: .banner)
                        .font(.subheadline.weight(.heavy))
                } else if isCurrent {
                    Text("Choosing")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TableTheme.goldBright)
                } else {
                    Text("—")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TableTheme.inkCreamDim)
                }
            }
            .padding(.horizontal, isCurrent ? 10 : 0)
            .padding(.vertical, isCurrent ? 7 : 0)
            .background(
                RoundedRectangle(cornerRadius: TableTheme.Radius.xs, style: .continuous)
                    .fill(isCurrent ? Color.black.opacity(0.36) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TableTheme.Radius.xs, style: .continuous)
                    .strokeBorder(isCurrent ? TableTheme.goldBright.opacity(0.85) : Color.clear,
                                  lineWidth: isCurrent ? 1 : 0)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .frame(minHeight: 84)
        .shadow(color: isCurrent ? TableTheme.goldBright.opacity(0.35) : .clear,
                radius: isCurrent ? 8 : 0)
    }

    /// Talon exchange: render the two prikup cards face-up centered on the
    /// felt so the declarer (and observers) see what the declarer just
    /// took. The hand fan also shows the same cards with a "P" badge for
    /// the discard interaction; this center view is purely informational.
    private var shouldShowPublicTalon: Bool {
        let hasKnownCards = projection.talon.contains { $0.knownCard != nil }
        switch projection.phase {
        case .awaitingDiscard:
            return hasKnownCards
        case .playing(_, _, kind: .allPass):
            return hasKnownCards
                && projection.rules.allPassTalonPolicy == .leadSuitOnly
                && projection.completedTrickCount < 2
        default:
            return false
        }
    }

    private func talonContext(title: LocalizedStringKey = "Prikup", size: CardView.Size = .standard) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(TableTheme.goldBright)
            HStack(spacing: 6) {
                ForEach(Array(projection.talon.enumerated()), id: \.offset) { _, card in
                    CardView(card: card, size: size, region: .talon)
                }
            }
        }
        .multilineTextAlignment(.center)
    }

    /// Centered Deal CTA shown on the empty felt during the pre-first-deal
    /// idle state. Replaces the old combination of (header pill + felt
    /// placeholder text + bottom action-bar button) with a single,
    /// optically centered button — the screen's one and only intent.
    private func startDealCenter(onStartDeal: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Button {
                onStartDeal()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Deal")
                        .fontWeight(.semibold)
                }
                .frame(minWidth: 200)
            }
            .buttonStyle(.feltPrimary)
            .accessibilityIdentifier(UIIdentifiers.buttonStartDeal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Deal-summary card

    /// Rich centered card shown when a deal has just been scored. Replaces
    /// the empty "Deal complete" placeholder with the outcome headline,
    /// per-player trick tally, and a prominent "Next deal" CTA so the user
    /// has something to look at and a clear action without dismissing a
    /// modal sheet.
    private func dealSummaryCard(result: DealResult) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text("Deal complete")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TableTheme.goldBright)
                    .tracking(1.4)
                    .textCase(.uppercase)
                Localized.dealResultHeadline(result, in: projection)
                    .font(.headline)
                    .foregroundStyle(TableTheme.inkCream)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier(UIIdentifiers.dealResultKind)
                Text(UIIdentifiers.encode(result.kind))
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            trickTallyGrid(result: result)
            if let initialHands = result.initialHands, !initialHands.isEmpty {
                openingHandsDisclosure(hands: initialHands, activePlayers: result.activePlayers)
            }
            if let onAdvance, projection.legal.canStartDeal {
                Button {
                    onAdvance()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("Next deal")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: 220)
                }
                .buttonStyle(.feltPrimary)
                .accessibilityIdentifier(UIIdentifiers.buttonStartDeal)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(dealSummaryBackground)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func openingHandsDisclosure(
        hands: [PlayerID: [Card]],
        activePlayers: [PlayerID]
    ) -> some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showInitialHands.toggle()
                }
            } label: {
                Label(
                    showInitialHands ? "Hide opening hands" : "Show opening hands",
                    systemImage: showInitialHands ? "eye.slash.fill" : "eye.fill"
                )
                .font(.caption.weight(.semibold))
                .frame(maxWidth: 220)
            }
            .buttonStyle(.feltSecondary)
            .accessibilityIdentifier("dealResult.initialHands.toggle")

            if showInitialHands {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(activePlayers, id: \.self) { player in
                            openingHandRow(player: player, cards: hands[player] ?? [])
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 250)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func openingHandRow(player: PlayerID, cards: [Card]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(projection.displayName(for: player))
                .font(.caption2.weight(.bold))
                .foregroundStyle(player == projection.viewer ? TableTheme.goldBright : TableTheme.inkCreamSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(openingHandRows(cards).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 4) {
                        ForEach(row, id: \.self) { card in
                            CardView(
                                card: .known(card),
                                size: .compact,
                                region: .hand(seat: player)
                            )
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dealResult.initialHand.\(player.rawValue)")
    }

    private func openingHandRows(_ cards: [Card]) -> [[Card]] {
        let sorted = cards.sorted()
        guard sorted.count > 5 else { return [sorted] }
        return [
            Array(sorted.prefix(5)),
            Array(sorted.dropFirst(5))
        ]
    }

    private var dealSummaryBackground: some View {
        RoundedRectangle(cornerRadius: TableTheme.Radius.md, style: .continuous)
            .fill(TableTheme.surfaceFill(.card))
            .overlay(
                RoundedRectangle(cornerRadius: TableTheme.Radius.md, style: .continuous)
                    .strokeBorder(TableTheme.surfaceBorder(.card), lineWidth: 1)
            )
    }

    /// Compact tricks-per-active-player grid. Sitting-out seats are excluded
    /// (they took zero tricks by definition); the declarer is highlighted in
    /// gold so the user can see at a glance whether the contract was met.
    private func trickTallyGrid(result: DealResult) -> some View {
        let players = result.activePlayers
        let declarer = declarer(for: result)
        return HStack(spacing: 8) {
            ForEach(players, id: \.self) { player in
                let isDeclarer = player == declarer
                VStack(spacing: 3) {
                    Text(projection.displayName(for: player))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isDeclarer ? TableTheme.goldBright : TableTheme.inkCream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(result.trickCounts[player] ?? 0)")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(isDeclarer ? TableTheme.goldBright : TableTheme.inkCream)
                        .accessibilityIdentifier(UIIdentifiers.seatTrickCount(player))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: TableTheme.Radius.xs, style: .continuous)
                        .fill(Color.black.opacity(isDeclarer ? 0.32 : 0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: TableTheme.Radius.xs, style: .continuous)
                        .strokeBorder(
                            isDeclarer ? TableTheme.goldBright.opacity(0.55) : TableTheme.inkCream.opacity(0.06),
                            lineWidth: isDeclarer ? 1 : 0.5
                        )
                )
            }
        }
    }

    private func declarer(for result: DealResult) -> PlayerID? {
        switch result.kind {
        case let .game(declarer, _, _):           return declarer
        case let .misere(declarer):               return declarer
        case let .halfWhist(declarer, _, _):      return declarer
        case .passedOut, .allPass:                return nil
        }
    }

    /// Played cards from the current trick, each anchored to its owner's
    /// seat slot with a small name caption below the card so a glance at
    /// the felt tells the user who played what. Replaces the previous
    /// raw-card layout where played cards drifted independently of seats.
    private func trickPlays(opponentSeats: [PlayerID]) -> some View {
        ZStack {
            ForEach(Array(projection.currentTrick.enumerated()), id: \.offset) { _, play in
                let pos = positionForPlay(player: play.player, opponents: opponentSeats)
                trickPlayMarker(play: play)
                    .matchedGeometryEffect(id: play.card, in: animationNamespace)
                    .offset(x: pos.width, y: pos.height)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// One played card + a subtle name caption. The caption stays below
    /// the card regardless of seat orientation so the eye reads the table
    /// consistently — no upside-down text for the top opponent.
    private func trickPlayMarker(play: CardPlay) -> some View {
        VStack(spacing: 3) {
            CardView(
                card: .known(play.card),
                size: .standard,
                region: .trick(seat: play.player)
            )
            Text(projection.displayName(for: play.player))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(TableTheme.inkCreamSoft)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.black.opacity(0.45), in: Capsule())
                .lineLimit(1)
        }
    }

    private func placeholder(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(TableTheme.inkCreamSoft)
            .tracking(0.5)
    }

    /// Viewer card lands at the bottom; opponents are placed around the
    /// felt in their seating order. Offsets are expressed as multiples of
    /// the trick-card dimensions so the layout still works if `CardView.Size`
    /// is ever retuned (or if we drop in a `.compact` trick on small phones).
    private func positionForPlay(player: PlayerID, opponents: [PlayerID]) -> CGSize {
        TableLayoutModel.trickOffset(for: player, viewer: projection.viewer, opponents: opponents)
    }

    /// Every seat except the viewer's, including the 4-player sitting-out
    /// dealer. The caller splits this into active vs sitting-out so the
    /// active opponents claim the main slot layout while the sitting-out
    /// seat is rendered as a compact corner chip — hiding the dealer
    /// entirely was confusing for users who couldn't see who's at the
    /// table during the deal they're sitting out.
    private func orderedOpponents() -> [SeatProjection] {
        projection.seats.filter { $0.player != projection.viewer }
    }
}
