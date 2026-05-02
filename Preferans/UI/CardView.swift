import SwiftUI
import PreferansEngine

public struct CardView: View {
    public var card: ProjectedCard
    public var isPlayable: Bool
    public var isSelected: Bool
    /// Region the card is rendered in. Drives the accessibility identifier
    /// so the same card description in different regions (hand vs talon vs
    /// trick) is uniquely addressable.
    public var region: UIIdentifiers.CardRegion?
    /// Position of the card in its row, used to disambiguate hidden cards
    /// in a defender's hand.
    public var indexInRow: Int

    public init(
        card: ProjectedCard,
        isPlayable: Bool = false,
        isSelected: Bool = false,
        region: UIIdentifiers.CardRegion? = nil,
        indexInRow: Int = 0
    ) {
        self.card = card
        self.isPlayable = isPlayable
        self.isSelected = isSelected
        self.region = region
        self.indexInRow = indexInRow
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
            .accessibilityIdentifier(identifier)
    }

    private var identifier: String {
        guard let region else { return "" }
        if let known = card.knownCard {
            return UIIdentifiers.card(known, in: region)
        }
        // Hidden card — only meaningful in a hand region. Other regions
        // never render hidden cards (talon/discard/trick are public).
        if case let .hand(seat) = region {
            return UIIdentifiers.hiddenCard(in: seat, index: indexInRow)
        }
        return ""
    }
}

public struct CardRowView: View {
    public var cards: [ProjectedCard]
    public var playableCards: Set<Card>
    public var selectedCards: Set<Card>
    public var region: UIIdentifiers.CardRegion?
    public var onTap: ((Card) -> Void)?

    public init(
        cards: [ProjectedCard],
        playableCards: Set<Card> = [],
        selectedCards: Set<Card> = [],
        region: UIIdentifiers.CardRegion? = nil,
        onTap: ((Card) -> Void)? = nil
    ) {
        self.cards = cards
        self.playableCards = playableCards
        self.selectedCards = selectedCards
        self.region = region
        self.onTap = onTap
    }

    public var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(cards.enumerated()), id: \.offset) { index, projected in
                    let known = projected.knownCard
                    CardView(
                        card: projected,
                        isPlayable: known.map { playableCards.contains($0) } ?? false,
                        isSelected: known.map { selectedCards.contains($0) } ?? false,
                        region: region,
                        indexInRow: index
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
