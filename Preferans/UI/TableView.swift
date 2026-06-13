import SwiftUI
import PreferansEngine

/// The central play area. Each opponent has a fixed slot above the felt;
/// the viewer's slot is at the bottom. The current trick cards land on
/// their owner's slot. During talon exchange the talon sits in the
/// middle of the felt for the declarer to pick from.
public struct TableView: View {
    private static let auctionStatusPillHeight: CGFloat = 34

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
    /// Presentation-only suit order for face-up table hands.
    public var cardSuitOrder: CardSuitDisplayOrder
    /// Currently selected card in a playable hand. Selection is visual only;
    /// double-tap or drag commits the play.
    public var selectedPlayCard: Card?
    public var onSelectPlayCard: ((Card) -> Void)?
    public var onPlayCard: ((PlayerID, Card) -> Void)?
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
        cardSuitOrder: CardSuitDisplayOrder = .default,
        selectedPlayCard: Card? = nil,
        onSelectPlayCard: ((Card) -> Void)? = nil,
        onPlayCard: ((PlayerID, Card) -> Void)? = nil,
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
        self.cardSuitOrder = cardSuitOrder
        self.selectedPlayCard = selectedPlayCard
        self.onSelectPlayCard = onSelectPlayCard
        self.onPlayCard = onPlayCard
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
                    sittingOutBand(sittingOut)
                    tableLayout(active: active)
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

    /// Sitting-out 4-player dealer(s) as a dedicated, centered row above the
    /// felt. Giving them their own band — instead of floating a chip into the
    /// opponent layout — is the only placement that can't overlap an active
    /// seat, since the two active seats span nearly the full width.
    @ViewBuilder
    private func sittingOutBand(_ seats: [SeatProjection]) -> some View {
        if !seats.isEmpty {
            HStack(spacing: 8) {
                ForEach(seats) { seat in
                    OpponentSeatView(
                        seat: seat,
                        orientation: .top,
                        cardSuitOrder: cardSuitOrder,
                        contractBid: projection.activeContractBid(for: seat.player),
                        lastAction: nil,
                        roleBadge: nil,
                        seatOrder: seatOrderNumber(for: seat.player),
                        showsTrickCount: showsTrickCount(for: seat),
                        playableCards: playableCards(for: seat.player),
                        selectedCards: selectedCards(for: seat.player),
                        onSelectCard: cardSelectHandler(for: seat.player),
                        onPlayCard: cardPlayHandler(for: seat.player),
                        onDragCard: cardPlayHandler(for: seat.player)
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Felt-wide tap target shown while the table is paused between card-play beats.
    @ViewBuilder
    private var tapToAdvanceOverlay: some View {
        if let advance = pendingAdvance {
            let onTap = onTapToAdvance
            ZStack {
                Color.black.opacity(onTap == nil ? 0.03 : (idleHintActive ? 0.18 : 0.05))
                    .allowsHitTesting(onTap != nil)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap?() }
                trickResultHint(advance: advance, canTap: onTap != nil)
                    .offset(y: advance.trickWinner == nil ? 0 : -74)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(onTap == nil ? UIIdentifiers.trickResultHold : UIIdentifiers.tapToAdvance)
            .transition(.opacity)
        }
    }

    private func trickResultHint(advance: PendingAdvance, canTap: Bool) -> some View {
        let waitingName = projection.displayName(for: advance.waitingOn)
        return VStack(spacing: 4) {
            if let winner = advance.trickWinner {
                Text("\(projection.displayName(for: winner)) took the trick")
                    .font(.headline.bold())
                    .foregroundStyle(TableTheme.goldBright)
                    .accessibilityIdentifier(UIIdentifiers.trickResultHold)
            } else if idleHintActive {
                Text("Waiting for \(waitingName)")
                    .font(.headline.bold())
                    .foregroundStyle(TableTheme.goldBright)
                    .accessibilityIdentifier(UIIdentifiers.waitingForViewer)
            }
            if canTap {
                Image(systemName: "hand.tap.fill")
                    .font(.caption)
                    .foregroundStyle(TableTheme.inkCream)
                    .accessibilityLabel(Text("Tap to continue"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, idleHintActive ? 10 : 8)
        .background(
            Capsule().fill(Color.black.opacity(idleHintActive ? 0.75 : 0.62))
        )
        .overlay(
            Capsule().strokeBorder(
                advance.trickWinner != nil || idleHintActive ? TableTheme.goldBright.opacity(0.7) : TableTheme.inkCream.opacity(0.15),
                lineWidth: advance.trickWinner != nil || idleHintActive ? 1.2 : 0.5
            )
        )
        .scaleEffect(idleHintActive ? 1.06 : 1.0)
        .shadow(color: advance.trickWinner != nil || idleHintActive ? TableTheme.goldBright.opacity(0.45) : .black.opacity(0.25),
                radius: advance.trickWinner != nil || idleHintActive ? 14 : 4)
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
    private func tableLayout(active: [SeatProjection]) -> some View {
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
                let playFrame = layout.playArea(for: active)
                playArea(opponentSeats: active.map(\.player))
                    .frame(width: playFrame.size.width,
                           height: playFrame.size.height)
                    .position(playFrame.position)

                // Active opponent seats positioned around the felt edge.
                ForEach(Array(layout.opponentSlots(opponents: active).enumerated()), id: \.offset) { _, slot in
                    let slotSize = layout.slotFrameSize(for: slot)
                    let isDeemphasized = active.contains { $0.player != slot.seat.player && isOpenHand($0) }
                        && !isOpenHand(slot.seat)
                    OpponentSeatView(
                        seat: slot.seat,
                        orientation: slot.orientation,
                        cardSuitOrder: cardSuitOrder,
                        contractBid: projection.activeContractBid(for: slot.seat.player),
                        isDeemphasized: isDeemphasized,
                        lastAction: seatActions[slot.seat.player],
                        roleBadge: seatRoleBadges[slot.seat.player],
                        seatOrder: seatOrderNumber(for: slot.seat.player),
                        showsTrickCount: showsTrickCount(for: slot.seat),
                        playableCards: playableCards(for: slot.seat.player),
                        selectedCards: selectedCards(for: slot.seat.player),
                        onSelectCard: cardSelectHandler(for: slot.seat.player),
                        onPlayCard: cardPlayHandler(for: slot.seat.player),
                        onDragCard: cardPlayHandler(for: slot.seat.player)
                    )
                    .frame(width: slotSize.width,
                           height: slotSize.height)
                    .position(x: slot.position.x * bounds.width,
                              y: slot.position.y * bounds.height)
                }

                // Centered action banner (transient toast). Sits above the
                // play area but ignores hit testing so it never blocks
                // taps on the trick or the deal-summary CTA. Suppressed
                // wherever the center surface already narrates the same
                // event: the auction panel's per-seat pills during
                // bidding, and the deal-summary / game-over cards at the
                // end of a deal.
                if showsActionBanner {
                    CenterActionBanner(
                        action: bannerAction,
                        displayName: { projection.displayName(for: $0) }
                    )
                    .position(layout.bannerPosition)
                }

                // Sitting-out dealer(s) are rendered as a dedicated band above
                // this layout (see `sittingOutBand`), not floated here: the two
                // active opponents are ~181 pt wide and nearly meet at center,
                // so any floating chip — corner or center — collided with a
                // seat (the "AgentSmith…OUT" overlap). A reserved row can't.
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
            GameOverCard(summary: summary, displayName: projection.displayName(for:), onRematch: onRematch, onLeaveTable: onLeaveTable)
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
        case .awaitingDiscard where !projection.legal.canDiscard:
            // Observers see the revealed prikup on the felt. The declarer
            // doesn't: those two cards are already merged into their hand
            // fan with "P" badges, so a center copy would show the same
            // cards twice on one screen.
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
        let active = projection.tableClockwiseAuctionSeats
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
            HStack(spacing: 4) {
                if seat.player == projection.viewer {
                    Text("You")
                } else {
                    Text(verbatim: seat.displayName)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(seat.player == projection.viewer ? TableTheme.inkCream : TableTheme.inkCreamSoft)
            .lineLimit(1)
            .minimumScaleFactor(0.62)
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
            .frame(maxWidth: .infinity)
            .frame(height: Self.auctionStatusPillHeight)
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

    /// Talon exchange: observers see the two prikup cards centered on the
    /// felt. The declarer sees those cards inside their 12-card discard fan
    /// with "P" badges instead, so they do not appear duplicated.
    private var shouldShowPublicTalon: Bool {
        let hasKnownCards = projection.talon.contains { $0.knownCard != nil }
        switch projection.phase {
        case .awaitingDiscard:
            // The declarer's hand fan already contains the two prikup cards
            // with badges during discard selection. Keep the center-table
            // copy for observers only so the acting player does not see a
            // confusing duplicate 12-card hand plus table talon.
            return hasKnownCards && !projection.legal.canDiscard
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
        let sorted = cards.sortedForTableDisplay(order: cardSuitOrder)
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
                trickPlayMarker(play: play, isWinner: play.player == pendingAdvance?.trickWinner)
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
    private func trickPlayMarker(play: CardPlay, isWinner: Bool) -> some View {
        VStack(spacing: 4) {
            // The played trick is the point of the screen — render it at the
            // largest card size so it reads as the centerpiece instead of a
            // small cluster lost in the felt. The winner keeps a gold ring:
            // it's a transient end-of-trick highlight, not persistent chrome,
            // and gold is the only accent that pops on a white card face.
            CardView(
                card: .known(play.card),
                size: .large,
                region: .trick(seat: play.player)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(
                        isWinner ? TableTheme.goldBright.opacity(0.95) : .clear,
                        lineWidth: isWinner ? 2 : 0
                    )
            )
            .shadow(color: isWinner ? TableTheme.goldBright.opacity(0.45) : .clear,
                    radius: isWinner ? 12 : 0)
            Text(trickPlayCaption(for: play.player))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isWinner ? TableTheme.feltDeep : TableTheme.inkCream)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(isWinner ? TableTheme.goldBright : Color.black.opacity(0.55), in: Capsule())
                .lineLimit(1)
        }
    }

    private func trickPlayCaption(for player: PlayerID) -> String {
        return projection.displayName(for: player)
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
        // Offsets are expressed in multiples of the trick-card size, so the
        // spread has to use the same `.large` size the markers now render at
        // or the bigger cards would overlap.
        TableLayoutModel.trickOffset(
            for: player,
            viewer: projection.viewer,
            opponents: opponents,
            cardSize: .large
        )
    }

    /// Every seat except the viewer's in clockwise table order, including
    /// the 4-player sitting-out dealer. The caller splits this into active
    /// vs sitting-out so the active opponents claim the main slot layout
    /// while the sitting-out seat is rendered as a compact corner chip —
    /// hiding the dealer entirely was confusing for users who couldn't see
    /// who's at the table during the deal they're sitting out.
    private func orderedOpponents() -> [SeatProjection] {
        projection.tableClockwiseOpponentSeats
    }

    private func seatOrderNumber(for player: PlayerID) -> Int? {
        projection.players.firstIndex(of: player).map { $0 + 1 }
    }

    private func playableCards(for player: PlayerID) -> Set<Card> {
        guard projection.legal.playableCardsOwner == player else { return [] }
        return Set(projection.legal.playableCards)
    }

    private func selectedCards(for player: PlayerID) -> Set<Card> {
        guard projection.legal.playableCardsOwner == player,
              let selectedPlayCard else { return [] }
        return [selectedPlayCard]
    }

    private func cardSelectHandler(for player: PlayerID) -> ((Card) -> Void)? {
        guard !playableCards(for: player).isEmpty else { return nil }
        return { card in onSelectPlayCard?(card) }
    }

    private func cardPlayHandler(for player: PlayerID) -> ((Card) -> Void)? {
        guard !playableCards(for: player).isEmpty else { return nil }
        return { card in onPlayCard?(player, card) }
    }

    private func isOpenHand(_ seat: SeatProjection) -> Bool {
        seat.hand.contains { $0.knownCard != nil }
    }

    /// False while the center felt is occupied by a surface that already
    /// narrates the latest action: the auction panel (per-seat call pills)
    /// or the deal-summary / game-over cards.
    private var showsActionBanner: Bool {
        switch projection.phase {
        case .bidding, .awaitingContract, .dealFinished, .gameOver:
            return false
        default:
            return true
        }
    }

    /// Mirror of the viewer name-plate rule: trick tallies only mean
    /// something once trick play has started (or a count is already on the
    /// board) — "0 tricks" under every seat during the deal wait and the
    /// auction is noise.
    private func showsTrickCount(for seat: SeatProjection) -> Bool {
        if seat.trickCount > 0 { return true }
        if case .playing = projection.phase { return true }
        return false
    }
}
