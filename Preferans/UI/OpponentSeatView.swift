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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(seatBackground)
        .opacity(seat.isActive ? 1 : 0.6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.seatContainer(seat.player))
    }

    /// A soft dark-felt pill grounds every seat; the active seat additionally
    /// gets a gold border + subtle warm glow so it reads as the place at the
    /// table that's currently in play.
    @ViewBuilder
    private var seatBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(seat.isCurrentActor ? 0.32 : 0.22))
            if seat.isCurrentActor {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        RadialGradient(
                            colors: [
                                TableTheme.goldBright.opacity(0.14),
                                TableTheme.goldBright.opacity(0.0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 80
                        )
                    )
            }
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    seat.isCurrentActor
                        ? TableTheme.goldBright.opacity(0.55)
                        : TableTheme.gold.opacity(0.10),
                    lineWidth: seat.isCurrentActor ? 1 : 0.5
                )
        }
    }

    private var statusRow: some View {
        let isSittingOut = seat.role == .sittingOut || (seat.isDealer && !seat.isActive)
        return HStack(spacing: 5) {
            if seat.isCurrentActor {
                Circle()
                    .fill(TableTheme.goldBright)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("Turn")
                    .accessibilityIdentifier(UIIdentifiers.seatCurrentActor(seat.player))
            }
            Text(seat.displayName)
                .font(.caption.bold())
                .foregroundStyle(seat.isCurrentActor ? TableTheme.goldBright : TableTheme.inkCream)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier(UIIdentifiers.scorePlayer(seat.player))
            // "Out" wins over "D" when a 4-player dealer is sitting out —
            // showing both pills crowds the seat and the dealer-and-out
            // combination is implied by the rules. Keep "D" only when the
            // dealer is also the active actor (3-player table).
            if isSittingOut {
                Text("Out")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .foregroundStyle(TableTheme.feltDeep)
                    .background(TableTheme.inkCreamSoft, in: Capsule())
                    .accessibilityLabel("Sitting out this deal")
                    .accessibilityIdentifier(UIIdentifiers.seatRole(seat.player))
            } else if seat.isDealer {
                Text("D")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .foregroundStyle(TableTheme.inkCreamSoft)
                    .background(Color.black.opacity(0.30), in: Capsule())
                    .accessibilityLabel("Dealer")
                    .accessibilityIdentifier(UIIdentifiers.seatDealer(seat.player))
            }
            Spacer(minLength: 0)
            Text("\(seat.trickCount)")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(TableTheme.inkCreamSoft)
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
