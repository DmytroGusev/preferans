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

    public init(
        projection: PlayerGameProjection,
        animationNamespace: Namespace.ID,
        onAdvance: (() -> Void)? = nil,
        onStartDeal: (() -> Void)? = nil
    ) {
        self.projection = projection
        self.animationNamespace = animationNamespace
        self.onAdvance = onAdvance
        self.onStartDeal = onStartDeal
    }

    public var body: some View {
        let opponents = orderedOpponents()
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(opponents) { seat in
                    OpponentSeatView(seat: seat)
                        .frame(maxWidth: .infinity)
                }
            }
            playArea(opponentSeats: opponents.map(\.player))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 160)
        }
    }

    /// Phase-aware text shown on the empty felt. Routed through `Localized`
    /// so the catalog is the single source of phase copy — title and felt
    /// placeholder live next to each other for translators.
    private var emptyFeltPlaceholder: LocalizedStringKey {
        Localized.feltPlaceholder(projection.phase)
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
            GameOverCard(summary: summary)
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
                    placeholder(emptyFeltPlaceholder)
                } else {
                    trickPlays(opponentSeats: opponentSeats)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(UIIdentifiers.Panel.currentTrick.rawValue)
        }
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

    private func trickPlays(opponentSeats: [PlayerID]) -> some View {
        ZStack {
            ForEach(Array(projection.currentTrick.enumerated()), id: \.offset) { _, play in
                let pos = positionForPlay(player: play.player, opponents: opponentSeats)
                CardView(
                    card: .known(play.card),
                    size: .standard,
                    region: .trick(seat: play.player)
                )
                .matchedGeometryEffect(id: play.card, in: animationNamespace)
                .offset(x: pos.width, y: pos.height)
                .transition(.scale.combined(with: .opacity))
            }
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
            let y = -h * 0.15
            return player == opponents[0] ? CGSize(width: -x, height: y) : CGSize(width: x, height: y)
        case 3:
            if player == opponents[0] { return CGSize(width: -w * 1.3, height: 0) }
            if player == opponents[1] { return CGSize(width: 0, height: -h * 0.75) }
            return CGSize(width: w * 1.3, height: 0)
        default:
            return .zero
        }
    }

    /// Hide the dealer-on-talon (sitting-out) seat. In 4-player Preferans the
    /// dealer doesn't take part in the deal — surfacing that seat just adds a
    /// dim, dealer-badged tile that the viewer can't interact with and that
    /// pushes the active opponents off-center.
    private func orderedOpponents() -> [SeatProjection] {
        projection.seats.filter { seat in
            guard seat.player != projection.viewer else { return false }
            if seat.role == .sittingOut { return false }
            return true
        }
    }
}
