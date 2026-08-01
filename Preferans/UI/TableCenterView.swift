import SwiftUI
import PreferansEngine

/// The center of the felt owns phase content, the current trick, and the
/// transient action explanation. Keeping this surface separate from the seat
/// layout makes the table's spatial composition explicit: the parent places
/// this view, while this view decides what the center should communicate.
struct TableCenterView: View {
    let projection: PlayerGameProjection
    let animationNamespace: Namespace.ID
    let opponentSeats: [PlayerID]
    let onAdvance: (() -> Void)?
    let onStartDeal: (() -> Void)?
    let onLeaveTable: (() -> Void)?
    let onRematch: (() -> Void)?
    let seatActions: [PlayerID: RecentAction]
    let pendingAdvance: PendingAdvance?
    let isTalonTakePending: Bool
    let isPadDevice: Bool
    let cardSuitOrder: CardSuitDisplayOrder
    let onTakeTalon: (() -> Void)?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if case let .gameOver(summary) = projection.phase {
                GameOverCard(
                    summary: summary,
                    displayName: projection.displayName(for:),
                    onRematch: onRematch,
                    onLeaveTable: onLeaveTable
                )
            } else if case let .dealFinished(result) = projection.phase {
                DealSummaryCard(
                    result: result,
                    projection: projection,
                    cardSuitOrder: cardSuitOrder,
                    onAdvance: onAdvance
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(UIIdentifiers.Panel.dealFinished.rawValue)
            } else if let onStartDeal, projection.legal.canStartDeal {
                startDealCenter(onStartDeal: onStartDeal)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(UIIdentifiers.Panel.currentTrick.rawValue)
            } else {
                ZStack {
                    if projection.currentTrick.isEmpty {
                        phaseContext()
                    } else {
                        trickPlays()
                        if shouldShowPublicTalon {
                            talonContext(
                                title: "Talon",
                                size: TableCenterLayoutPolicy.publicTalonCardSize(
                                    for: horizontalSizeClass,
                                    isPadDevice: isPadDevice
                                )
                            )
                                .offset(y: -96)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(UIIdentifiers.Panel.currentTrick.rawValue)
            }
        }
    }

    @ViewBuilder
    private func phaseContext() -> some View {
        switch projection.phase {
        case .awaitingDiscard where isTalonTakePending:
            talonContext(action: onTakeTalon)
        case .awaitingDiscard where !projection.legal.canDiscard:
            talonContext()
        case .playing(_, _, kind: .allPass) where shouldShowPublicTalon:
            talonContext(title: "Talon")
        case .bidding, .awaitingContract:
            AuctionContextView(projection: projection, seatActions: seatActions)
        default:
            EmptyView()
        }
    }

    private var shouldShowPublicTalon: Bool {
        let hasKnownCards = projection.talon.contains { $0.knownCard != nil }
        switch projection.phase {
        case .awaitingDiscard:
            return hasKnownCards && (isTalonTakePending || !projection.legal.canDiscard)
        case .playing(_, _, kind: .allPass):
            let usesTalonLeads: Bool
            switch projection.rules.allPassTalonPolicy {
            case .classic, .leadSuitOnly: usesTalonLeads = true
            case .ignored: usesTalonLeads = false
            }
            return hasKnownCards && usesTalonLeads && projection.completedTrickCount < 2
        default:
            return false
        }
    }

    @ViewBuilder
    private func talonContext(
        title: LocalizedStringKey = "Prikup",
        size: CardView.Size? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        let cardSize = size ?? TableCenterLayoutPolicy.talonCardSize(
            for: horizontalSizeClass,
            isPadDevice: isPadDevice
        )
        let content = VStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(TableTheme.goldBright)
            HStack(spacing: 6) {
                ForEach(Array(projection.talon.enumerated()), id: \.offset) { _, card in
                    CardView(card: card, size: cardSize, region: .talon)
                }
            }
            if action != nil {
                Label("Take prikup", systemImage: "hand.tap.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TableTheme.feltDeep)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(TableTheme.goldBright, in: Capsule())
            }
        }
        .multilineTextAlignment(.center)

        if let action {
            Button {
                action()
            } label: {
                content
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: TableTheme.Radius.md, style: .continuous)
                            .fill(Color.black.opacity(0.20))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: TableTheme.Radius.md, style: .continuous)
                            .strokeBorder(TableTheme.goldBright.opacity(0.65), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(UIIdentifiers.buttonTakeTalon)
        } else {
            content
        }
    }

    private func startDealCenter(onStartDeal: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Button {
                onStartDeal()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Deal")
                        .fontWeight(.semibold)
                }
                .frame(minWidth: 200)
            }
            .buttonStyle(.feltPrimary)
            .accessibilityIdentifier(UIIdentifiers.buttonStartDeal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func trickPlays() -> some View {
        let cardSize = TableCenterLayoutPolicy.trickCardSize(
            for: horizontalSizeClass,
            isPadDevice: isPadDevice
        )
        return ZStack {
            ForEach(Array(projection.currentTrick.enumerated()), id: \.offset) { _, play in
                let pos = TableLayoutModel.trickOffset(
                    for: play.player,
                    viewer: projection.viewer,
                    opponents: opponentSeats,
                    cardSize: cardSize
                )
                trickPlayMarker(
                    play: play,
                    cardSize: cardSize,
                    isWinner: play.player == pendingAdvance?.trickWinner
                )
                    .matchedGeometryEffect(id: play.card, in: animationNamespace)
                    .offset(x: pos.width, y: pos.height)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func trickPlayMarker(
        play: CardPlay,
        cardSize: CardView.Size,
        isWinner: Bool
    ) -> some View {
        VStack(spacing: 4) {
            CardView(
                card: .known(play.card),
                size: cardSize,
                region: .trick(seat: play.player)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(
                        isWinner ? TableTheme.goldBright.opacity(0.95) : .clear,
                        lineWidth: isWinner ? 2 : 0
                    )
            )
            .shadow(
                color: isWinner ? TableTheme.goldBright.opacity(0.45) : .clear,
                radius: isWinner ? 12 : 0
            )
            Text(projection.displayName(for: play.player))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isWinner ? TableTheme.feltDeep : TableTheme.inkCream)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(isWinner ? TableTheme.goldBright : Color.black.opacity(0.55), in: Capsule())
                .lineLimit(1)
        }
    }

}

/// The trick is the most spatially sensitive phase of the table. Compact
/// iPhone surfaces keep the center readable without letting large cards crowd
/// the hand rail; iPad tables keep the larger center cards even when Split View
/// reports a compact horizontal size class.
enum TableCenterLayoutPolicy {
    static func trickCardSize(
        for horizontalSizeClass: UserInterfaceSizeClass?,
        isPadDevice: Bool = false
    ) -> CardView.Size {
        isPadDevice || horizontalSizeClass == .regular ? .large : .standard
    }

    /// A talon lead shares the felt with the current trick. Keep it compact on
    /// iPhone so the two surfaces do not collide, but let regular-width iPad
    /// tables use the same readable large cards as their other public cards.
    static func publicTalonCardSize(
        for horizontalSizeClass: UserInterfaceSizeClass?,
        isPadDevice: Bool = false
    ) -> CardView.Size {
        isPadDevice || horizontalSizeClass == .regular ? .large : .compact
    }

    static func talonCardSize(
        for horizontalSizeClass: UserInterfaceSizeClass?,
        isPadDevice: Bool = false
    ) -> CardView.Size {
        isPadDevice || horizontalSizeClass == .regular ? .large : .standard
    }
}
