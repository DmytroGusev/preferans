import SwiftUI
import PreferansEngine

public enum CardSuitDisplayOrder: String, CaseIterable, Identifiable, Sendable {
    case spadesDiamondsClubsHearts
    case clubsDiamondsSpadesHearts
    case diamondsClubsHeartsSpades
    case spadesClubsDiamondsHearts

    public var id: String { rawValue }

    public static let `default`: CardSuitDisplayOrder = .spadesDiamondsClubsHearts

    public var suits: [Suit] {
        switch self {
        case .spadesDiamondsClubsHearts:
            return [.spades, .diamonds, .clubs, .hearts]
        case .clubsDiamondsSpadesHearts:
            return [.clubs, .diamonds, .spades, .hearts]
        case .diamondsClubsHeartsSpades:
            return [.diamonds, .clubs, .hearts, .spades]
        case .spadesClubsDiamondsHearts:
            return [.spades, .clubs, .diamonds, .hearts]
        }
    }

    public var displayName: String {
        suits.map(\.symbol).joined(separator: " ")
    }

    func index(of suit: Suit) -> Int {
        suits.firstIndex(of: suit) ?? suit.rawValue
    }
}

extension Card {
    static func tableDisplayLessThan(
        _ lhs: Card,
        _ rhs: Card,
        order: CardSuitDisplayOrder = .default
    ) -> Bool {
        if lhs.suit != rhs.suit {
            return order.index(of: lhs.suit) < order.index(of: rhs.suit)
        }
        return lhs.rank < rhs.rank
    }
}

extension Array where Element == Card {
    func sortedForTableDisplay(order: CardSuitDisplayOrder = .default) -> [Card] {
        sorted { Card.tableDisplayLessThan($0, $1, order: order) }
    }
}

extension Array where Element == ProjectedCard {
    func sortedForTableDisplay(order: CardSuitDisplayOrder = .default) -> [ProjectedCard] {
        sorted { lhs, rhs in
            switch (lhs.knownCard, rhs.knownCard) {
            case let (left?, right?):
                return Card.tableDisplayLessThan(left, right, order: order)
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return false
            }
        }
    }
}

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
    /// True when this card came from the prikup and is being displayed inside
    /// the declarer's hand fan during discard. Drives a "P" corner badge so
    /// the user can tell their original 10 cards from the 2 prikup additions.
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
                Text("badge.prikup")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.orange, in: Capsule())
                    .padding(2)
                    .accessibilityLabel("From the prikup")
            }
        }
        .shadow(color: .black.opacity(isPlayable ? 0.30 : 0.10), radius: isPlayable ? 6 : 2, y: isPlayable ? 3 : 1)
        .scaleEffect(isSelected ? 1.10 : 1)
        .offset(y: isSelected ? -8 : (isPlayable ? -3 : 0))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.description)
        .accessibilityIdentifier(identifier)
        .accessibilityAddTraits(.isButton)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isSelected)
    }

    private func cardFace(known: Card) -> some View {
        let color = known.suit.color(on: .cardFace)
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
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.32, green: 0.06, blue: 0.08),
                        Color(red: 0.18, green: 0.03, blue: 0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            RoundedRectangle(cornerRadius: size.cornerRadius - 2)
                .strokeBorder(Color(red: 0.83, green: 0.67, blue: 0.34).opacity(0.55), lineWidth: 0.8)
                .padding(3)
            Image(systemName: "suit.club.fill")
                .font(size.pipFont)
                .foregroundStyle(Color(red: 0.83, green: 0.67, blue: 0.34).opacity(0.65))
        }
    }

    private var borderColor: Color {
        if isSelected { return .accentColor }
        return .black.opacity(0.18)
    }

    private var borderWidth: CGFloat {
        isSelected ? 2 : 0.6
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
