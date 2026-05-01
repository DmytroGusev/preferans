import SwiftUI
import PreferansEngine

public struct CardView: View {
    public var card: ProjectedCard
    public var isPlayable: Bool
    public var isSelected: Bool

    public init(card: ProjectedCard, isPlayable: Bool = false, isSelected: Bool = false) {
        self.card = card
        self.isPlayable = isPlayable
        self.isSelected = isSelected
    }

    public var body: some View {
        Text(card.description)
            .font(.title3.monospaced().bold())
            .frame(width: 46, height: 62)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isPlayable || isSelected ? .primary : .secondary, lineWidth: isPlayable || isSelected ? 2 : 1)
            }
            .scaleEffect(isSelected ? 1.08 : 1)
            .opacity(card.knownCard == nil ? 0.72 : 1)
            .accessibilityLabel(card.description)
    }
}

public struct CardRowView: View {
    public var cards: [ProjectedCard]
    public var playableCards: Set<Card>
    public var selectedCards: Set<Card>
    public var onTap: ((Card) -> Void)?

    public init(cards: [ProjectedCard], playableCards: Set<Card> = [], selectedCards: Set<Card> = [], onTap: ((Card) -> Void)? = nil) {
        self.cards = cards
        self.playableCards = playableCards
        self.selectedCards = selectedCards
        self.onTap = onTap
    }

    public var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(cards.enumerated()), id: \.offset) { _, projected in
                    let known = projected.knownCard
                    CardView(
                        card: projected,
                        isPlayable: known.map { playableCards.contains($0) } ?? false,
                        isSelected: known.map { selectedCards.contains($0) } ?? false
                    )
                    .onTapGesture {
                        if let known { onTap?(known) }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}
