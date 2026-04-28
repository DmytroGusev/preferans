import SwiftUI

extension Suit {
    var color: Color {
        switch self {
        case .diamonds, .hearts:
            return Color(red: 0.69, green: 0.13, blue: 0.11)
        case .clubs, .spades:
            return Color(red: 0.08, green: 0.08, blue: 0.1)
        }
    }

    var title: String {
        rawValue.capitalized
    }
}

extension Phase {
    var title: String {
        switch self {
        case .setup: return "Setup"
        case .bidding: return "Bidding"
        case .takingTalon: return "Talon"
        case .discarding: return "Discard"
        case .declaringContract: return "Contract"
        case .whisting: return "Whist"
        case .playing: return "Play"
        case .handFinished: return "Finished"
        }
    }
}

struct PlayingCardView: View {
    let card: Card
    var faceUp: Bool = true
    var isPlayable: Bool = true
    var isCompact: Bool = false
    var scale: CGFloat = 1
    var isSelected: Bool = false

    private var cornerRadius: CGFloat {
        isCompact ? 10 : 14
    }

    var body: some View {
        ZStack {
            if faceUp {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 0.995, green: 0.99, blue: 0.975))

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.22), lineWidth: 1)

                VStack {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(card.rank.label)
                                .font(.system(size: isCompact ? 11 : 14, weight: .black, design: .serif))
                                .minimumScaleFactor(0.9)
                            Text(card.suit.symbol)
                                .font(.system(size: isCompact ? 10 : 13, weight: .black, design: .serif))
                                .minimumScaleFactor(0.9)
                        }
                        .foregroundStyle(card.suit.color)

                        Spacer(minLength: 0)
                    }

                    Spacer(minLength: 0)
                }
                .padding(isCompact ? 6 : 7)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(red: 0.06, green: 0.22, blue: 0.19))

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color(red: 0.82, green: 0.69, blue: 0.39), lineWidth: 1)

                RoundedRectangle(cornerRadius: max(6, cornerRadius - 4), style: .continuous)
                    .inset(by: isCompact ? 7 : 9)
                    .stroke(Color(red: 0.82, green: 0.69, blue: 0.39).opacity(0.7), lineWidth: 1)

                Image(systemName: "suit.spade.fill")
                    .font(.system(size: isCompact ? 17 : 28, weight: .bold))
                    .foregroundStyle(Color(red: 0.92, green: 0.85, blue: 0.69))
            }
        }
        .frame(
            width: (isCompact ? 58 : 98) * scale,
            height: (isCompact ? 86 : 158) * scale
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    isSelected ? Color(red: 0.88, green: 0.74, blue: 0.38) : Color.clear,
                    lineWidth: isSelected ? 2 : 0
                )
        )
    }
}

struct SeatBadgeView: View {
    let player: Player
    let isActive: Bool
    let isDeclarer: Bool
    var isPassed: Bool = false
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(player.name)
                    .font((compact ? Font.caption : .subheadline).weight(.semibold))
                    .foregroundStyle(.white)
                if isDeclarer {
                    Text("Declarer")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(red: 0.8, green: 0.64, blue: 0.28))
                        .foregroundStyle(.black)
                        .clipShape(Capsule())
                }
                if isPassed {
                    Text("Pass")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.12))
                        .foregroundStyle(.white.opacity(0.9))
                        .clipShape(Capsule())
                }
            }
            HStack(spacing: 10) {
                Text("Pool \(player.pool)")
                Text("Mt \(player.mountain)")
                Text("Net \(player.score)")
            }
            .font(compact ? .caption2 : .caption)
            .foregroundStyle(.white.opacity(0.78))
        }
        .padding(compact ? 8 : 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    isActive
                    ? Color(red: 0.57, green: 0.42, blue: 0.15).opacity(0.85)
                    : (isPassed ? Color.black.opacity(0.14) : Color.black.opacity(0.25))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(isActive ? 0.16 : (isPassed ? 0.12 : 0.08)), lineWidth: 1)
        )
        .opacity(isPassed ? 0.74 : 1)
    }
}

struct FanHandView: View {
    let cards: [Card]
    let playableCards: Set<Card>
    let onTap: (Card) -> Void

    var body: some View {
        GeometryReader { geometry in
            let count = max(cards.count, 1)
            let centerX = geometry.size.width / 2
            let baseY = geometry.size.height * 0.56

            ZStack {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    let progress = count == 1 ? 0.0 : Double(index) / Double(count - 1)
                    let angle = -10.0 + progress * 20.0
                    let xOffset = CGFloat(progress - 0.5) * min(geometry.size.width * 0.72, CGFloat(count) * 24)
                    let isPlayable = playableCards.contains(card)

                    Button {
                        onTap(card)
                    } label: {
                        PlayingCardView(card: card, isPlayable: isPlayable)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isPlayable)
                    .rotationEffect(.degrees(angle))
                    .position(
                        x: centerX + xOffset,
                        y: baseY - abs(xOffset) * 0.02 - (isPlayable ? 10 : 0)
                    )
                    .zIndex(Double(index))
                }
            }
        }
    }
}

struct PreviewHandView: View {
    let cards: [Card]
    var playableCards: Set<Card> = []
    var selectedCardIDs: Set<String> = []
    var onTap: ((Card) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let count = max(cards.count, 1)
            let baseWidth: CGFloat = 98
            let visibleFactor: CGFloat = count > 8 ? 0.46 : 0.56
            let availableWidth = max(geometry.size.width - 12, 1)
            let fittedScale = availableWidth / (baseWidth * (1 + visibleFactor * CGFloat(count - 1)))
            let scale = min(0.84, max(0.58, fittedScale))
            let cardWidth = baseWidth * scale
            let spacing = -cardWidth * (1 - visibleFactor)

            HStack(spacing: spacing) {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                    let isInteractive = onTap != nil
                    let isPlayable = !isInteractive || playableCards.contains(card)

                    Button {
                        onTap?(card)
                    } label: {
                        PlayingCardView(
                            card: card,
                            isPlayable: isPlayable,
                            scale: scale,
                            isSelected: selectedCardIDs.contains(card.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isPlayable)
                    .offset(y: selectedCardIDs.contains(card.id) ? -10 : 0)
                    .zIndex(Double(index))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
    }
}

struct CardBackStackView: View {
    let count: Int
    var maxVisible: Int = 5
    var scale: CGFloat = 0.46

    var body: some View {
        HStack(spacing: -22 * scale) {
            ForEach(0..<min(max(count, 0), maxVisible), id: \.self) { _ in
                PlayingCardView(
                    card: Card(suit: .spades, rank: .ace),
                    faceUp: false,
                    isPlayable: true,
                    isCompact: true,
                    scale: scale
                )
            }

            if count > maxVisible {
                Text("+\(count - maxVisible)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.86))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.28))
                    .clipShape(Capsule())
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Text("\(count)")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Color(red: 0.92, green: 0.85, blue: 0.69))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.38))
                .clipShape(Capsule())
                .offset(x: 10, y: 7)
        }
        .opacity(count == 0 ? 0.3 : 1)
    }
}
