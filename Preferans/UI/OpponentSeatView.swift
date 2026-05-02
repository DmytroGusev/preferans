import SwiftUI
import PreferansEngine

/// Compact opponent seat: shows the player name, status badges (dealer,
/// turn, role), trick count, and a small fan of card backs (or revealed
/// cards if the projection exposes them).
public struct OpponentSeatView: View {
    public var seat: SeatProjection

    public init(seat: SeatProjection) {
        self.seat = seat
    }

    public var body: some View {
        VStack(spacing: 4) {
            statusRow
            cardBacksRow
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(seat.isCurrentActor ? Color.accentColor.opacity(0.18) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(seat.isCurrentActor ? Color.accentColor : .clear, lineWidth: 1.5)
        }
        .opacity(seat.isActive ? 1 : 0.5)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.seatContainer(seat.player))
    }

    private var statusRow: some View {
        HStack(spacing: 5) {
            if seat.isCurrentActor {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Turn")
                    .accessibilityIdentifier(UIIdentifiers.seatCurrentActor(seat.player))
            }
            Text(seat.displayName)
                .font(.caption.bold())
                .lineLimit(1)
                .accessibilityIdentifier(UIIdentifiers.scorePlayer(seat.player))
            if seat.isDealer {
                Text("D")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .foregroundStyle(.secondary)
                    .background(Color.secondary.opacity(0.18), in: Capsule())
                    .accessibilityLabel("Dealer")
                    .accessibilityIdentifier(UIIdentifiers.seatDealer(seat.player))
            }
            Spacer(minLength: 0)
            Text("\(seat.trickCount)")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Tricks: \(seat.trickCount)")
                .accessibilityIdentifier(UIIdentifiers.seatTrickCount(seat.player))
        }
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
