import SwiftUI
import PreferansEngine

/// Renders a player's hand as an overlapping fan that always fits the
/// available width — no horizontal scrolling. Cards overlap when the
/// hand is wide; selecting/playable cards rise above the fan.
public struct CardFanView: View {
    public var cards: [ProjectedCard]
    public var playableCards: Set<Card>
    public var selectedCards: Set<Card>
    public var seat: PlayerID
    public var size: CardView.Size
    /// Geometry namespace shared with the table so hand → trick movement
    /// can animate via matchedGeometryEffect.
    public var animationNamespace: Namespace.ID?
    public var onTap: ((Card) -> Void)?

    public init(
        cards: [ProjectedCard],
        playableCards: Set<Card> = [],
        selectedCards: Set<Card> = [],
        seat: PlayerID,
        size: CardView.Size = .standard,
        animationNamespace: Namespace.ID? = nil,
        onTap: ((Card) -> Void)? = nil
    ) {
        self.cards = cards
        self.playableCards = playableCards
        self.selectedCards = selectedCards
        self.seat = seat
        self.size = size
        self.animationNamespace = animationNamespace
        self.onTap = onTap
    }

    public var body: some View {
        let cardWidth = size.dimensions.width
        let cardHeight = size.dimensions.height
        let count = cards.count

        GeometryReader { geo in
            let available = geo.size.width
            let step = stepWidth(available: available, cardWidth: cardWidth, count: count)
            let totalWidth = step * CGFloat(max(0, count - 1)) + cardWidth
            let startX = max(0, (available - totalWidth) / 2)

            ZStack(alignment: .topLeading) {
                ForEach(Array(cards.enumerated()), id: \.offset) { index, projected in
                    let known = projected.knownCard
                    let isPlayable = known.map { playableCards.contains($0) } ?? false
                    let isSelected = known.map { selectedCards.contains($0) } ?? false
                    cardView(projected, index: index, known: known, isPlayable: isPlayable, isSelected: isSelected)
                        .offset(x: startX + step * CGFloat(index), y: 0)
                        .zIndex(Double(index) + (isSelected || isPlayable ? 100 : 0))
                        .onTapGesture {
                            if let known { onTap?(known) }
                        }
                }
            }
            .frame(width: available, height: cardHeight + 12, alignment: .topLeading)
        }
        .frame(height: cardHeight + 12)
    }

    @ViewBuilder
    private func cardView(_ projected: ProjectedCard, index: Int, known: Card?, isPlayable: Bool, isSelected: Bool) -> some View {
        let view = CardView(
            card: projected,
            isPlayable: isPlayable,
            isSelected: isSelected,
            size: size,
            region: .hand(seat: seat),
            indexInRow: index
        )
        if let ns = animationNamespace, let known {
            view.matchedGeometryEffect(id: known, in: ns)
        } else {
            view
        }
    }

    private func stepWidth(available: CGFloat, cardWidth: CGFloat, count: Int) -> CGFloat {
        guard count > 1 else { return 0 }
        let natural = cardWidth * 0.78
        let maxStepThatFits = (available - cardWidth) / CGFloat(count - 1)
        return min(natural, max(cardWidth * 0.32, maxStepThatFits))
    }
}
