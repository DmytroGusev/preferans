import SwiftUI
import PreferansEngine

/// Opponent seat rendered as a real face-down hand fan + a quiet name
/// chip — no dark box. The fan shows one card back per card the opponent
/// actually holds, so a 10-card hand reads as ten cards and a 1-card
/// late-trick hand reads as one. Hands wider than ~5 cards wrap to a
/// second row so the seat footprint stays compact and readable from the
/// viewer's perspective regardless of where the seat sits at the table.
public struct OpponentSeatView: View {
    public var seat: SeatProjection
    /// Position relative to the viewer. Drives a tiny visual offset (no
    /// rotation any more — every opponent's hand reads horizontally from
    /// the viewer's POV so cards never rotate vertically and clip the
    /// trick area).
    public var orientation: Orientation

    public enum Orientation {
        case top
        case left
        case right
    }

    public init(seat: SeatProjection, orientation: Orientation = .top) {
        self.seat = seat
        self.orientation = orientation
    }

    public var body: some View {
        VStack(spacing: 3) {
            nameChip
            fan
        }
        .opacity(seat.isActive ? 1 : 0.55)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.seatContainer(seat.player))
    }

    /// One-line player chip: name + dealer/sitting-out/turn pill + trick
    /// count. No background box — sits directly on the felt with just a
    /// gold underline when this seat is acting.
    private var nameChip: some View {
        HStack(spacing: 6) {
            if seat.isCurrentActor {
                Circle()
                    .fill(TableTheme.goldBright)
                    .frame(width: 6, height: 6)
                    .accessibilityIdentifier(UIIdentifiers.seatCurrentActor(seat.player))
            }
            Text(seat.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(seat.isCurrentActor ? TableTheme.goldBright : TableTheme.inkCream)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityIdentifier(UIIdentifiers.scorePlayer(seat.player))

            statusBadge

            Text("\(seat.trickCount)")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(TableTheme.inkCreamSoft)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .overlay(
                    Capsule().strokeBorder(TableTheme.inkCream.opacity(0.18), lineWidth: 0.5)
                )
                .accessibilityLabel("\(seat.trickCount) tricks")
                .accessibilityIdentifier(UIIdentifiers.seatTrickCount(seat.player))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if seat.role == .sittingOut {
            Text("OUT")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(TableTheme.feltDeep)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(TableTheme.inkCreamSoft, in: Capsule())
                .accessibilityIdentifier(UIIdentifiers.seatRole(seat.player))
        } else if seat.isDealer {
            Text("D")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(TableTheme.inkCream)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.black.opacity(0.30), in: Capsule())
                .accessibilityIdentifier(UIIdentifiers.seatDealer(seat.player))
        }
    }

    /// Render one card back per card the opponent really holds, wrapping
    /// to a second row once the hand is wider than `cardsPerRow`. Every
    /// row is horizontal — even side seats — so cards never rotate
    /// vertically into the trick area. The first row gets the leading
    /// half; the second row stacks above it slightly inset so the fan
    /// reads as a held hand rather than two separate piles.
    private var fan: some View {
        let count = seat.hand.count
        let dims = CardView.Size.compact.dimensions
        let cardsPerRow = 5
        let rows = splitIntoRows(count: count, perRow: cardsPerRow)
        return VStack(spacing: -dims.height * 0.55) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, rowCount in
                fanRow(count: rowCount, cardSize: dims)
            }
        }
        .frame(height: count == 0 ? 0 : rowsHeight(rowCount: rows.count, cardHeight: dims.height))
    }

    /// One horizontal row of face-down cards. Cards overlap by ~50% so a
    /// 5-card row stays narrow enough that three opponent fans fit on
    /// the upper third of an iPhone width without collisions.
    private func fanRow(count: Int, cardSize dims: CGSize) -> some View {
        let step: CGFloat = -dims.width * 0.50
        return HStack(spacing: step) {
            ForEach(0..<count, id: \.self) { index in
                CardView(
                    card: .hidden,
                    size: .compact,
                    region: .hand(seat: seat.player),
                    indexInRow: index
                )
            }
        }
    }

    /// Two-row split for hands wider than `perRow`. Top row gets the
    /// remainder, bottom row gets the full row — that way 10 cards split
    /// 5+5, 9 cards split 4+5, etc.
    private func splitIntoRows(count: Int, perRow: Int) -> [Int] {
        guard count > 0 else { return [] }
        if count <= perRow { return [count] }
        let bottom = perRow
        let top = count - perRow
        return [top, bottom]
    }

    private func rowsHeight(rowCount: Int, cardHeight: CGFloat) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        // Each subsequent row contributes only the visible 45% slice
        // (since the rows overlap by 55%).
        return cardHeight + CGFloat(rowCount - 1) * cardHeight * 0.45
    }
}
