import SwiftUI
import PreferansEngine

/// The viewer's bottom hand and identity lane. Selection and game actions stay
/// in `ProjectionGameScreen`; this component receives an explicit presentation
/// snapshot so compact and regular layouts can choose their own card scale.
struct ViewerHandRail: View {
    @Environment(\.tableTheme) private var theme

    let seat: SeatProjection
    let viewer: PlayerID
    let viewerDisplayName: String
    let seatOrder: Int?
    let roleBadge: SeatRoleBadge?
    let lastAction: RecentAction?
    let showsTrickCount: Bool
    let cards: [ProjectedCard]
    let playableCards: Set<Card>
    let selectedCards: Set<Card>
    let talonCards: Set<Card>
    let cardSize: CardView.Size
    let animationNamespace: Namespace.ID
    let onTap: ((Card) -> Void)?
    let onDoubleTap: ((Card) -> Void)?
    let onDragEnded: ((Card) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                CardFanView(
                    cards: cards,
                    playableCards: playableCards,
                    selectedCards: selectedCards,
                    talonCards: talonCards,
                    seat: seat.player,
                    size: cardSize,
                    animationNamespace: animationNamespace,
                    onTap: onTap,
                    onDoubleTap: onDoubleTap,
                    onDragEnded: onDragEnded
                )
                .shadow(
                    color: seat.isCurrentActor ? theme.accentStrong.opacity(0.35) : .clear,
                    radius: seat.isCurrentActor ? 12 : 0
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(UIIdentifiers.seatContainer(seat.player))

                if seat.isCurrentActor {
                    actorAccessibilityMarker
                }
            }
            namePlate
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    private var actorAccessibilityMarker: some View {
        Text("Acting")
            .frame(width: 0, height: 0)
            .clipped()
            .opacity(0)
            .accessibilityIdentifier(UIIdentifiers.seatCurrentActor(viewer))
    }

    private var viewerAccessibilityLabel: some View {
        Text(AccessibilityStrings.viewerLabelPrefix + viewerDisplayName)
            .font(.caption2)
            .frame(width: 1, height: 1)
            .clipped()
            .opacity(0.001)
            .accessibilityIdentifier(UIIdentifiers.viewerLabel)
    }

    private var namePlate: some View {
        HStack(spacing: 8) {
            if let seatOrder {
                SeatOrderBadge(
                    number: seatOrder,
                    player: seat.player,
                    isCurrentActor: seat.isCurrentActor
                )
            }
            Text(seat.displayName)
                .font(.caption.bold())
                .foregroundStyle(theme.textPrimary)
                .accessibilityIdentifier(UIIdentifiers.scorePlayer(seat.player))
                .accessibilityLabel("Viewing as \(viewerDisplayName)")
                .accessibilityValue("you")
            viewerAccessibilityLabel
            statusPill
            if let roleBadge {
                rolePill(roleBadge)
            }
            if let lastAction {
                lastActionPill(lastAction)
            }
            Spacer(minLength: 4)
            if showsTrickCount {
                Text("\(seat.trickCount)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(theme.textSecondary)
                    .accessibilityLabel("\(seat.trickCount) tricks")
                    .accessibilityIdentifier(UIIdentifiers.seatTrickCount(seat.player))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }

    private func rolePill(_ badge: SeatRoleBadge) -> some View {
        Text(badge.label)
            .font(.caption2.weight(.bold))
            .tracking(0.3)
            .foregroundStyle(badge.isAccent ? theme.onAccent : theme.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                Capsule().fill(
                    badge.isAccent
                        ? theme.accent
                        : theme.shade.opacity(0.30)
                )
            )
            .accessibilityIdentifier(UIIdentifiers.seatRoleBadge(seat.player))
    }

    private func lastActionPill(_ action: RecentAction) -> some View {
        HStack(spacing: 4) {
            action.label.glyph(emphasis: .seat)
                .font(.caption2.weight(.bold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(Capsule().fill(theme.accent.opacity(0.20)))
        .overlay(
            Capsule().strokeBorder(theme.accent.opacity(0.45), lineWidth: 0.5)
        )
        .accessibilityIdentifier(UIIdentifiers.seatLastAction(action.player))
    }

    @ViewBuilder
    private var statusPill: some View {
        if seat.isCurrentActor {
            Text("Your turn")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .foregroundStyle(theme.onAccent)
                .background(theme.accentStrong, in: Capsule())
                .accessibilityIdentifier(UIIdentifiers.seatCurrentActor(seat.player))
        } else if seat.role == .sittingOut {
            Text("Sitting out")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .foregroundStyle(theme.textSecondary)
                .background(theme.shade.opacity(0.30), in: Capsule())
                .accessibilityIdentifier(UIIdentifiers.seatRole(seat.player))
        } else if seat.isDealer {
            Text("Dealer")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .foregroundStyle(theme.textSecondary)
                .background(theme.shade.opacity(0.30), in: Capsule())
                .accessibilityIdentifier(UIIdentifiers.seatDealer(seat.player))
        }
    }
}
