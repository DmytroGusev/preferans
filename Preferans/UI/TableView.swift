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

    public init(
        projection: PlayerGameProjection,
        animationNamespace: Namespace.ID,
        onAdvance: (() -> Void)? = nil,
        onStartDeal: (() -> Void)? = nil,
        onLeaveTable: (() -> Void)? = nil,
        onRematch: (() -> Void)? = nil,
        renderOpponentsAtTop: Bool = true
    ) {
        self.projection = projection
        self.animationNamespace = animationNamespace
        self.onAdvance = onAdvance
        self.onStartDeal = onStartDeal
        self.onLeaveTable = onLeaveTable
        self.onRematch = onRematch
        self.renderOpponentsAtTop = renderOpponentsAtTop
    }

    public var body: some View {
        let opponents = orderedOpponents()
        if renderOpponentsAtTop {
            VStack(spacing: 4) {
                DealStateStrip(projection: projection)
                tableLayout(opponents: opponents)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            playArea(opponentSeats: opponents.map(\.player))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 200)
        }
    }

    /// Real card-table layout: opponents are positioned around the felt
    /// (top, left, right) at their seat slots — not stacked
    /// shoulder-to-shoulder at the top. The trick area sits in the center
    /// and grows to fill the available real estate.
    private func tableLayout(opponents: [SeatProjection]) -> some View {
        GeometryReader { geo in
            let bounds = geo.size
            ZStack {
                // Center: trick area / phase content. Sized smaller than
                // the felt so seat fans can sit at the edges without
                // overlapping it.
                // Center the play area in the open felt below the
                // opponent row. Every opponent slot now lives in the
                // upper third (y ≤ ~0.30) so the trick area can claim
                // the lower two-thirds and stay optically centered for
                // every seat configuration.
                playArea(opponentSeats: opponents.map(\.player))
                    .frame(width: max(0, bounds.width * 0.86),
                           height: max(0, bounds.height * 0.62))
                    .position(x: bounds.width * 0.5, y: bounds.height * 0.62)

                // Opponent seats positioned around the felt edge.
                ForEach(Array(opponentSlots(opponents: opponents).enumerated()), id: \.offset) { _, slot in
                    OpponentSeatView(seat: slot.seat, orientation: slot.orientation)
                        .frame(width: slotFrameSize(for: slot, bounds: bounds).width,
                               height: slotFrameSize(for: slot, bounds: bounds).height)
                        .position(x: slot.position.x * bounds.width,
                                  y: slot.position.y * bounds.height)
                }
            }
            .frame(width: bounds.width, height: bounds.height)
        }
        .frame(minHeight: 320)
    }

    /// One slot per opponent — its position (normalised 0–1 of the felt),
    /// its orientation hint for the fan, and its frame size category. The
    /// number of opponents drives where each seat lands:
    ///   - 1 opponent → top center
    ///   - 2 opponents → top-left + top-right
    ///   - 3 opponents → upper-left + top + upper-right (every fan
    ///     horizontal — no rotated vertical columns)
    private func opponentSlots(opponents: [SeatProjection]) -> [OpponentSlot] {
        switch opponents.count {
        case 1:
            return [OpponentSlot(seat: opponents[0], position: CGPoint(x: 0.5, y: 0.16), orientation: .top, kind: .topWide)]
        case 2:
            return [
                OpponentSlot(seat: opponents[0], position: CGPoint(x: 0.25, y: 0.18), orientation: .top, kind: .topNarrow),
                OpponentSlot(seat: opponents[1], position: CGPoint(x: 0.75, y: 0.18), orientation: .top, kind: .topNarrow),
            ]
        case 3:
            // Top opponent sits highest; left/right step down so the
            // three horizontal fans cascade rather than collide
            // shoulder-to-shoulder. The vertical stagger also makes the
            // table read as "around" rather than "across".
            return [
                OpponentSlot(seat: opponents[0], position: CGPoint(x: 0.18, y: 0.26), orientation: .left, kind: .topNarrow),
                OpponentSlot(seat: opponents[1], position: CGPoint(x: 0.50, y: 0.10), orientation: .top, kind: .topNarrow),
                OpponentSlot(seat: opponents[2], position: CGPoint(x: 0.82, y: 0.26), orientation: .right, kind: .topNarrow),
            ]
        default:
            return opponents.enumerated().map { idx, seat in
                let x = (CGFloat(idx) + 1) / CGFloat(opponents.count + 1)
                return OpponentSlot(seat: seat, position: CGPoint(x: x, y: 0.18), orientation: .top, kind: .topNarrow)
            }
        }
    }

    private func slotFrameSize(for slot: OpponentSlot, bounds: CGSize) -> CGSize {
        switch slot.kind {
        case .topWide:
            return CGSize(width: min(bounds.width * 0.78, 320), height: 130)
        case .topNarrow:
            // Wide enough for "Agent Smith" + the trick-count chip without
            // truncating, and tall enough to clear two rows of compact
            // card backs.
            return CGSize(width: min(bounds.width * 0.32, 160), height: 130)
        }
    }

    fileprivate struct OpponentSlot {
        var seat: SeatProjection
        var position: CGPoint
        var orientation: OpponentSeatView.Orientation
        var kind: Kind
        enum Kind { case topWide, topNarrow }
    }

    /// The center of the felt where the current trick sits. The felt is the
    /// screen background; this view only places the trick / phase-message
    /// content into the open middle. The prikup is intentionally rendered
    /// only inside the viewer's hand fan during discard (each card carrying a
    /// "P" badge), so the center felt stays a single source of truth instead
    /// of a duplicated picker.
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
        default:
            EmptyView()
        }
    }

    /// Talon exchange: render the two prikup cards face-up centered on the
    /// felt so the declarer (and observers) see what the declarer just
    /// took. The hand fan also shows the same cards with a "P" badge for
    /// the discard interaction; this center view is purely informational.
    private func talonContext() -> some View {
        VStack(spacing: 8) {
            Text("Prikup")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(TableTheme.goldBright)
            HStack(spacing: 6) {
                ForEach(Array(projection.talon.enumerated()), id: \.offset) { _, card in
                    CardView(card: card, size: .standard)
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
        let dims = CardView.Size.standard.dimensions
        let w = dims.width
        let h = dims.height
        if player == projection.viewer { return CGSize(width: 0, height: h * 0.7) }
        switch opponents.count {
        case 1:
            return CGSize(width: 0, height: -h * 0.7)
        case 2:
            let x = w * 1.1
            let y = -h * 0.45
            return player == opponents[0] ? CGSize(width: -x, height: y) : CGSize(width: x, height: y)
        case 3:
            // Side opponents are now positioned horizontally in the
            // upper third — pull their played cards both inward and
            // upward so they hover under the seat fans rather than
            // floating in the middle row.
            if player == opponents[0] { return CGSize(width: -w * 1.05, height: -h * 0.55) }
            if player == opponents[1] { return CGSize(width: 0, height: -h * 0.85) }
            return CGSize(width: w * 1.05, height: -h * 0.55)
        default:
            return .zero
        }
    }

    /// Every seat except the viewer's, including the 4-player sitting-out
    /// dealer. The sitting-out seat is rendered dimmed (with an "OUT"
    /// badge) so the user always sees the full table — hiding the
    /// dealer entirely was confusing for users who couldn't see who's
    /// at the table during the deal they're sitting out.
    private func orderedOpponents() -> [SeatProjection] {
        projection.seats.filter { $0.player != projection.viewer }
    }
}
