import SwiftUI
import PreferansEngine

/// Bidding-phase center cluster. It is independent of the surrounding seat
/// layout so the table center can be composed without extending `TableView`.
struct AuctionContextView: View {
    @Environment(\.tableTheme) private var theme

    let projection: PlayerGameProjection
    let seatActions: [PlayerID: RecentAction]

    private static var auctionStatusPillHeight: CGFloat { 34 }

    var body: some View {
        let active = projection.tableClockwiseAuctionSeats
        return VStack(spacing: 14) {
            auctionPanelTitle
            HStack(spacing: 0) {
                ForEach(Array(active.enumerated()), id: \.element.player) { index, seat in
                    auctionSeatPill(seat: seat)
                        .frame(maxWidth: .infinity)
                    if index < active.count - 1 {
                        Rectangle()
                            .fill(theme.accent.opacity(0.22))
                            .frame(width: 0.5, height: 70)
                            .padding(.horizontal, 8)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: TableTheme.Radius.md, style: .continuous)
                .fill(theme.shade.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: TableTheme.Radius.md, style: .continuous)
                .strokeBorder(theme.accent.opacity(0.34), lineWidth: 0.75)
        )
        .multilineTextAlignment(.center)
    }

    private var auctionPanelTitle: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(theme.accent.opacity(0.38))
                .frame(height: 0.6)
            Text("Auction")
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(theme.accentStrong)
                .fixedSize()
            Rectangle()
                .fill(theme.accent.opacity(0.38))
                .frame(height: 0.6)
        }
    }

    private func auctionSeatPill(seat: SeatProjection) -> some View {
        let action = seatActions[seat.player]
        let isCurrent = seat.isCurrentActor
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                if seat.player == projection.viewer {
                    Text("You")
                } else {
                    Text(verbatim: seat.displayName)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(seat.player == projection.viewer ? theme.textPrimary : theme.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.62)
            Group {
                if let action {
                    action.label.glyph(emphasis: .banner)
                        .font(.subheadline.weight(.heavy))
                } else if isCurrent {
                    ViewThatFits(in: .horizontal) {
                        Text("Choosing")
                            .fixedSize()
                        Text("…")
                            .accessibilityLabel("Choosing")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.accentStrong)
                } else {
                    Text("—")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.textMuted)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.auctionStatusPillHeight)
            .background(
                RoundedRectangle(cornerRadius: TableTheme.Radius.xs, style: .continuous)
                    .fill(isCurrent ? theme.shade.opacity(0.36) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TableTheme.Radius.xs, style: .continuous)
                    .strokeBorder(isCurrent ? theme.accentStrong.opacity(0.85) : Color.clear,
                                  lineWidth: isCurrent ? 1 : 0)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .frame(minHeight: 84)
        .shadow(color: isCurrent ? theme.accentStrong.opacity(0.35) : .clear,
                radius: isCurrent ? 8 : 0)
    }
}
