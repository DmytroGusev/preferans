import SwiftUI
import PreferansEngine

/// The central play area. Each opponent has a fixed slot above the felt;
/// the viewer's slot is at the bottom. The current trick cards land on
/// their owner's slot. During talon exchange the talon sits in the
/// middle of the felt for the declarer to pick from.
public struct TableView: View {
    public var projection: PlayerGameProjection
    public var animationNamespace: Namespace.ID

    public init(projection: PlayerGameProjection, animationNamespace: Namespace.ID) {
        self.projection = projection
        self.animationNamespace = animationNamespace
    }

    public var body: some View {
        let opponents = orderedOpponents()
        VStack(spacing: 6) {
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

    /// The center of the felt where the current trick sits. The felt is the
    /// screen background; this view only places the trick / phase-message
    /// content into the open middle. The talon is intentionally rendered
    /// only inside the viewer's hand fan during discard (each card carrying a
    /// "T" badge), so the center felt stays a single source of truth instead
    /// of a duplicated picker.
    private func playArea(opponentSeats: [PlayerID]) -> some View {
        ZStack {
            if projection.legal.canStartDeal {
                placeholder("Tap Start Deal")
            } else if projection.currentTrick.isEmpty {
                placeholder(emptyFeltPlaceholder)
            } else {
                trickPlays(opponentSeats: opponentSeats)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.Panel.currentTrick.rawValue)
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

    /// Phase-aware text shown on the empty felt. "Waiting for first card" only
    /// makes sense once we're in the trick-play phase; bidding/whist/contract
    /// phases get their own copy.
    private var emptyFeltPlaceholder: LocalizedStringKey {
        switch projection.phase {
        case .bidding:                   return "Auction in progress"
        case .awaitingContract:          return "Declarer is naming the contract"
        case .awaitingWhist:             return "Defenders are calling whist"
        case .awaitingDefenderMode:      return "Whister is choosing open or closed"
        case .playing:                   return "Waiting for first card"
        case .waitingForDeal:            return "Tap Start Deal"
        case .dealFinished, .gameOver:   return "Deal complete"
        case .awaitingDiscard:           return "Choose 2 cards to discard"
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
            if seat.isDealer && !seat.isActive { return false }
            return true
        }
    }
}
