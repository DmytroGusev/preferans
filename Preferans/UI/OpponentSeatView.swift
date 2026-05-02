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
        .background(seatBackground)
        .opacity(seat.isActive ? 1 : 0.55)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.seatContainer(seat.player))
    }

    /// Active seats get a soft pool of light suggesting a "place at the
    /// table"; inactive seats sit directly on the felt with no chrome.
    @ViewBuilder
    private var seatBackground: some View {
        if seat.isCurrentActor {
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    RadialGradient(
                        colors: [
                            TableTheme.goldBright.opacity(0.18),
                            TableTheme.goldBright.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 90
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(TableTheme.goldBright.opacity(0.55), lineWidth: 1)
                }
        } else {
            Color.clear
        }
    }

    private var statusRow: some View {
        HStack(spacing: 5) {
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
                .accessibilityIdentifier(UIIdentifiers.scorePlayer(seat.player))
            if seat.isDealer {
                Text("D")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .foregroundStyle(TableTheme.inkCreamSoft)
                    .background(Color.black.opacity(0.30), in: Capsule())
                    .accessibilityLabel("Dealer")
                    .accessibilityIdentifier(UIIdentifiers.seatDealer(seat.player))
            }
            // 4-player only: dealer sits out the deal entirely. Make that
            // explicit with a dedicated pill so the seat doesn't read as
            // "loading" on a compact iPhone layout.
            if seat.role == .sittingOut || (seat.isDealer && !seat.isActive) {
                Text("Out")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .foregroundStyle(TableTheme.feltDeep)
                    .background(TableTheme.inkCreamSoft, in: Capsule())
                    .accessibilityLabel("Sitting out this deal")
                    .accessibilityIdentifier(UIIdentifiers.seatRole(seat.player))
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
