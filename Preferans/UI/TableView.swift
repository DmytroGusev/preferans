import SwiftUI
import PreferansEngine

/// The central play area. Each opponent has a fixed slot above the felt;
/// the viewer's slot is at the bottom. The current trick cards land on
/// their owner's slot. During talon exchange the talon sits in the
/// middle of the felt for the declarer to pick from.
public struct TableView: View {
    public var projection: PlayerGameProjection
    public var animationNamespace: Namespace.ID

    public init(projection: PlayerGameProjection, animationNamespace: Namespace.ID) {
        self.projection = projection
        self.animationNamespace = animationNamespace
    }

    public var body: some View {
        let opponents = orderedOpponents()
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(opponents) { seat in
                    OpponentSeatView(seat: seat)
                        .frame(maxWidth: .infinity)
                }
            }
            playArea(opponentSeats: opponents.map(\.player))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 160)
        }
    }

    /// The center of the felt where the current trick or talon sits. The
    /// felt is the screen background; this view only places the trick /
    /// talon / phase-message content into the open middle.
    private func playArea(opponentSeats: [PlayerID]) -> some View {
        ZStack {
            if projection.legal.canStartDeal {
                placeholder("Tap Start Deal")
            } else if showsTalonOnFelt {
                talonOnFelt
            } else if projection.currentTrick.isEmpty {
                placeholder(emptyFeltPlaceholder)
            } else {
                trickPlays(opponentSeats: opponentSeats)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.Panel.currentTrick.rawValue)
    }

    private func trickPlays(opponentSeats: [PlayerID]) -> some View {
        ZStack {
            ForEach(Array(projection.currentTrick.enumerated()), id: \.offset) { _, play in
                let pos = positionForPlay(player: play.player, opponents: opponentSeats)
                CardView(
                    card: .known(play.card),
                    size: .standard,
                    region: .trick(seat: play.player)
                )
                .matchedGeometryEffect(id: play.card, in: animationNamespace)
                .offset(x: pos.width, y: pos.height)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var talonOnFelt: some View {
        VStack(spacing: 6) {
            Text("Talon")
                .font(.caption.bold())
                .foregroundStyle(TableTheme.inkCreamSoft)
                .tracking(1.2)
                .textCase(.uppercase)
            HStack(spacing: 6) {
                ForEach(Array(projection.talon.enumerated()), id: \.offset) { index, projected in
                    CardView(
                        card: projected,
                        size: .standard,
                        region: .talon,
                        indexInRow: index
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.Panel.talon.rawValue)
    }

    private func placeholder(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(TableTheme.inkCreamSoft)
            .tracking(0.5)
    }

    /// Viewer card lands at the bottom; opponents are placed around the
    /// felt in their seating order.
    private func positionForPlay(player: PlayerID, opponents: [PlayerID]) -> CGSize {
        if player == projection.viewer { return CGSize(width: 0, height: 50) }
        switch opponents.count {
        case 1:
            return CGSize(width: 0, height: -50)
        case 2:
            return player == opponents[0] ? CGSize(width: -55, height: -10) : CGSize(width: 55, height: -10)
        case 3:
            if player == opponents[0] { return CGSize(width: -65, height: 0) }
            if player == opponents[1] { return CGSize(width: 0, height: -55) }
            return CGSize(width: 65, height: 0)
        default:
            return .zero
        }
    }

    private var showsTalonOnFelt: Bool {
        if case .awaitingDiscard = projection.phase { return true }
        return false
    }

    /// Phase-aware text shown on the empty felt. "Waiting for first card" only
    /// makes sense once we're in the trick-play phase; bidding/whist/contract
    /// phases get their own copy.
    private var emptyFeltPlaceholder: LocalizedStringKey {
        switch projection.phase {
        case .bidding:                   return "Auction in progress"
        case .awaitingContract:          return "Declarer is naming the contract"
        case .awaitingWhist:             return "Defenders are calling whist"
        case .awaitingDefenderMode:      return "Whister is choosing open or closed"
        case .playing:                   return "Waiting for first card"
        case .waitingForDeal:            return "Tap Start Deal"
        case .dealFinished, .gameOver:   return "Deal complete"
        case .awaitingDiscard:           return ""
        }
    }

    private func orderedOpponents() -> [SeatProjection] {
        projection.seats.filter { $0.player != projection.viewer }
    }
}
