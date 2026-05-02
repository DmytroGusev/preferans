import SwiftUI
import PreferansEngine

public struct CardView: View {
    public enum Size {
        case standard
        case compact
        case large

        var dimensions: CGSize {
            switch self {
            case .compact:  return CGSize(width: 38, height: 54)
            case .standard: return CGSize(width: 52, height: 74)
            case .large:    return CGSize(width: 64, height: 92)
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .compact:  return 5
            case .standard: return 7
            case .large:    return 9
            }
        }

        var rankFont: Font {
            switch self {
            case .compact:  return .system(size: 11, weight: .bold, design: .rounded)
            case .standard: return .system(size: 14, weight: .bold, design: .rounded)
            case .large:    return .system(size: 17, weight: .bold, design: .rounded)
            }
        }

        var pipFont: Font {
            switch self {
            case .compact:  return .system(size: 11, weight: .bold)
            case .standard: return .system(size: 14, weight: .bold)
            case .large:    return .system(size: 17, weight: .bold)
            }
        }

        var centerFont: Font {
            switch self {
            case .compact:  return .system(size: 22, weight: .bold)
            case .standard: return .system(size: 30, weight: .bold)
            case .large:    return .system(size: 38, weight: .bold)
            }
        }
    }

    public var card: ProjectedCard
    public var isPlayable: Bool
    public var isSelected: Bool
    /// True when this card came from the talon and is being displayed inside
    /// the declarer's hand fan during discard. Drives a "T" corner badge so
    /// the user can tell their original 10 cards from the 2 talon additions.
    public var isTalon: Bool
    public var size: Size
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
        isTalon: Bool = false,
        size: Size = .standard,
        region: UIIdentifiers.CardRegion? = nil,
        indexInRow: Int = 0
    ) {
        self.card = card
        self.isPlayable = isPlayable
        self.isSelected = isSelected
        self.isTalon = isTalon
        self.size = size
        self.region = region
        self.indexInRow = indexInRow
    }

    public var body: some View {
        let dims = size.dimensions
        Group {
            if let known = card.knownCard {
                cardFace(known: known)
            } else {
                cardBack
            }
        }
        .frame(width: dims.width, height: dims.height)
        .overlay {
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        }
        .overlay(alignment: .topTrailing) {
            if isTalon {
                Text("T")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.orange, in: Capsule())
                    .padding(2)
                    .accessibilityLabel("From talon")
            }
        }
        .shadow(color: .black.opacity(isPlayable ? 0.22 : 0.10), radius: isPlayable ? 5 : 2, y: 1)
        .scaleEffect(isSelected ? 1.10 : 1)
        .offset(y: isSelected ? -8 : 0)
        .accessibilityLabel(card.description)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(.isButton)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isSelected)
    }

    private func cardFace(known: Card) -> some View {
        let color = suitColor(known.suit)
        let pad: CGFloat = size == .compact ? 3 : 4
        return ZStack {
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(Color.white)
            VStack {
                HStack(alignment: .top) {
                    pip(rank: known.rank, suit: known.suit, color: color)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                HStack(alignment: .bottom) {
                    Spacer(minLength: 0)
                    pip(rank: known.rank, suit: known.suit, color: color)
                        .rotationEffect(.degrees(180))
                }
            }
            .padding(pad)
            Text(known.suit.symbol)
                .font(size.centerFont)
                .foregroundStyle(color)
        }
    }

    private func pip(rank: Rank, suit: Suit, color: Color) -> some View {
        VStack(spacing: 0) {
            Text(rank.symbol)
                .font(size.rankFont)
            Text(suit.symbol)
                .font(size.pipFont)
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .fixedSize()
    }

    private var cardBack: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size.cornerRadius)
                .fill(Color(red: 0.13, green: 0.30, blue: 0.55))
            RoundedRectangle(cornerRadius: size.cornerRadius - 2)
                .stroke(Color.white.opacity(0.45), lineWidth: 1)
                .padding(3)
            Image(systemName: "suit.club.fill")
                .font(size.pipFont)
                .foregroundStyle(Color.white.opacity(0.55))
        }
    }

    private func suitColor(_ suit: Suit) -> Color {
        switch suit {
        case .hearts, .diamonds: return Color(red: 0.78, green: 0.10, blue: 0.10)
        case .spades, .clubs:    return .black
        }
    }

    private var borderColor: Color {
        if isSelected { return .accentColor }
        if isPlayable { return .accentColor.opacity(0.85) }
        return .black.opacity(0.18)
    }

    private var borderWidth: CGFloat {
        isPlayable || isSelected ? 2 : 0.6
    }

    private var identifier: String {
        guard let region else { return "" }
        if let known = card.knownCard {
            return UIIdentifiers.card(known, in: region)
        }
        if case let .hand(seat) = region {
            return UIIdentifiers.hiddenCard(in: seat, index: indexInRow)
        }
        return ""
    }
}

