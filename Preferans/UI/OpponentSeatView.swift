import SwiftUI
import PreferansEngine

/// Opponent seat tile: name, status badges, trick count, and a small fan
/// of card backs. Sits at the top of the table; styled as a flat
/// `feltSurface` chip so every chip on the felt — opponent seat, action
/// bar, phase pill — reads as the same material.
public struct OpponentSeatView: View {
    public var seat: SeatProjection

    public init(seat: SeatProjection) {
        self.seat = seat
    }

    public var body: some View {
        VStack(spacing: 6) {
            statusRow
            cardBacksRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .feltSurface(seat.isCurrentActor ? .seatActive : .seat,
                     radius: TableTheme.Radius.sm)
        .opacity(seat.isActive ? 1 : 0.55)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.seatContainer(seat.player))
    }

    private var statusRow: some View {
        let isSittingOut = seat.role == .sittingOut
        return HStack(spacing: 6) {
            if seat.isCurrentActor {
                Circle()
                    .fill(TableTheme.goldBright)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("Turn")
                    .accessibilityIdentifier(UIIdentifiers.seatCurrentActor(seat.player))
            }
            Text(seat.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(seat.isCurrentActor ? TableTheme.goldBright : TableTheme.inkCream)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier(UIIdentifiers.scorePlayer(seat.player))
            // "Sitting out" wins over "D" when a 4-player dealer is sitting out —
            // showing both pills crowds the seat and the dealer-and-out
            // combination is implied by the rules. Keep "D" only when the
            // dealer is also the active actor (3-player table).
            if isSittingOut {
                badgePill("Out", role: .sittingOut)
                    .accessibilityLabel("Sitting out this deal")
                    .accessibilityIdentifier(UIIdentifiers.seatRole(seat.player))
            } else if seat.isDealer {
                badgePill("D", role: .dealer)
                    .accessibilityLabel("Dealer")
                    .accessibilityIdentifier(UIIdentifiers.seatDealer(seat.player))
            }
            Spacer(minLength: 0)
            Text("\(seat.trickCount)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(TableTheme.inkCreamSoft)
                .accessibilityLabel("\(seat.trickCount) tricks")
                .accessibilityIdentifier(UIIdentifiers.seatTrickCount(seat.player))
        }
    }

    private enum BadgeRole { case sittingOut, dealer }

    private func badgePill(_ text: String, role: BadgeRole) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.5)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(role == .sittingOut ? TableTheme.feltDeep : TableTheme.inkCreamSoft)
            .background(
                Capsule().fill(role == .sittingOut
                               ? TableTheme.inkCreamSoft
                               : Color.black.opacity(0.30))
            )
    }

    /// Opponents always render as card backs — the projection's hand
    /// contents stay private regardless of revealAll debug toggles.
    private var cardBacksRow: some View {
        let count = seat.hand.count
        let visible = min(count, 4)
        return HStack(spacing: -22) {
            ForEach(0..<visible, id: \.self) { index in
                CardView(
                    card: .hidden,
                    size: .compact,
                    region: .hand(seat: seat.player),
                    indexInRow: index
                )
            }
        }
        .frame(height: count == 0 ? 0 : CardView.Size.compact.dimensions.height)
    }
}
