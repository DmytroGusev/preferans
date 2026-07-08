import SwiftUI
import PreferansEngine

// MARK: - Auction panel

extension TableView {
    private static var auctionStatusPillHeight: CGFloat { 34 }

    /// Bidding-phase center cluster. One pill per active seat showing
    /// the latest call (bid / pass) or a quiet "…" while the seat is
    /// still pending. The current caller's pill is ringed in gold so
    /// the eye lands on whose turn it is. Replaces the small
    /// auction-trail row at the top of the strip as the primary read
    /// of "where is the auction".
    func biddingContext() -> some View {
        let active = projection.tableClockwiseAuctionSeats
        return VStack(spacing: 14) {
            auctionPanelTitle
            HStack(spacing: 0) {
                ForEach(Array(active.enumerated()), id: \.element.player) { index, seat in
                    auctionSeatPill(seat: seat)
                        .frame(maxWidth: .infinity)
                    if index < active.count - 1 {
                        Rectangle()
                            .fill(TableTheme.gold.opacity(0.22))
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
                .fill(Color.black.opacity(0.16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: TableTheme.Radius.md, style: .continuous)
                .strokeBorder(TableTheme.gold.opacity(0.34), lineWidth: 0.75)
        )
        .multilineTextAlignment(.center)
    }

    private var auctionPanelTitle: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(TableTheme.gold.opacity(0.38))
                .frame(height: 0.6)
            Text("Auction")
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(TableTheme.goldBright)
                .fixedSize()
            Rectangle()
                .fill(TableTheme.gold.opacity(0.38))
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
            .foregroundStyle(seat.player == projection.viewer ? TableTheme.inkCream : TableTheme.inkCreamSoft)
            .lineLimit(1)
            .minimumScaleFactor(0.62)
            Group {
                if let action {
                    action.label.glyph(emphasis: .banner)
                        .font(.subheadline.weight(.heavy))
                } else if isCurrent {
                    Text("Choosing")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TableTheme.goldBright)
                } else {
                    Text("—")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TableTheme.inkCreamDim)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.auctionStatusPillHeight)
            .background(
                RoundedRectangle(cornerRadius: TableTheme.Radius.xs, style: .continuous)
                    .fill(isCurrent ? Color.black.opacity(0.36) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TableTheme.Radius.xs, style: .continuous)
                    .strokeBorder(isCurrent ? TableTheme.goldBright.opacity(0.85) : Color.clear,
                                  lineWidth: isCurrent ? 1 : 0)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .frame(minHeight: 84)
        .shadow(color: isCurrent ? TableTheme.goldBright.opacity(0.35) : .clear,
                radius: isCurrent ? 8 : 0)
    }
}
