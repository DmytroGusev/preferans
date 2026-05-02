import SwiftUI
import PreferansEngine

public struct PlayerHandView: View {
    public var seat: SeatProjection
    public var playableCards: Set<Card>
    public var selectedCards: Set<Card>
    public var onCardTap: ((Card) -> Void)?

    public init(seat: SeatProjection, playableCards: Set<Card> = [], selectedCards: Set<Card> = [], onCardTap: ((Card) -> Void)? = nil) {
        self.seat = seat
        self.playableCards = playableCards
        self.selectedCards = selectedCards
        self.onCardTap = onCardTap
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(seat.displayName)
                    .font(.headline)
                    .accessibilityIdentifier(UIIdentifiers.scorePlayer(seat.player))
                if seat.isDealer {
                    Text("Dealer")
                        .font(.caption)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.thinMaterial, in: Capsule())
                        .accessibilityIdentifier(UIIdentifiers.seatDealer(seat.player))
                }
                if seat.isCurrentActor {
                    Text("Turn")
                        .font(.caption.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.thinMaterial, in: Capsule())
                        .accessibilityIdentifier(UIIdentifiers.seatCurrentActor(seat.player))
                }
                Text(seat.role.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(UIIdentifiers.seatRole(seat.player))
                Spacer()
                Text("Tricks: \(seat.trickCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(UIIdentifiers.seatTrickCount(seat.player))
            }
            CardRowView(
                cards: seat.hand,
                playableCards: playableCards,
                selectedCards: selectedCards,
                region: .hand(seat: seat.player),
                onTap: onCardTap
            )
        }
        .padding(.vertical, 4)
        .opacity(seat.isActive ? 1 : 0.45)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.seatContainer(seat.player))
    }
}
