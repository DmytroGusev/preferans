import SwiftUI
import PreferansEngine

/// Opponent seat rendered as a real face-down hand fan + a quiet name
/// chip — no dark box. The fan shows one card back per card the opponent
/// actually holds, so a 10-card hand reads as ten cards and a 1-card
/// late-trick hand reads as one. The name chip floats above the fan with
/// turn / dealer / sitting-out indicators inline.
public struct OpponentSeatView: View {
    public var seat: SeatProjection
    /// Position relative to the viewer. Drives the rotation applied to the
    /// fan so the fan visually "points" at its owner's side of the table:
    /// top opponents get an upside-down fan, side opponents get a 90°
    /// rotation. Compact iPhone defaults to .top — there's no horizontal
    /// room to rotate fans 90° without clipping the trick area.
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
        Group {
            switch orientation {
            case .top:
                VStack(spacing: 3) {
                    nameChip
                    fan
                }
            case .left, .right:
                VStack(spacing: 4) {
                    nameChip
                    rotatedFan(rotation: orientation == .left ? .degrees(90) : .degrees(-90))
                }
            }
        }
        .opacity(seat.isActive ? 1 : 0.55)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.seatContainer(seat.player))
    }

    /// Side-positioned fan: a horizontal fan rotated 90° so the cards
    /// stand upright next to the table edge. The wrapping frame
    /// dimensions match the post-rotation footprint so layout doesn't
    /// have to "see" through the rotation transform.
    private func rotatedFan(rotation: Angle) -> some View {
        let count = seat.hand.count
        let dims = CardView.Size.compact.dimensions
        guard count > 0 else {
            // Sitting-out seat — no fan, but reserve a slim vertical
            // strip so the seat tile keeps the same height as its peers.
            return AnyView(Color.clear.frame(width: dims.height, height: 24))
        }
        let preferredStep: CGFloat = -dims.width * 0.40
        let originalWidth: CGFloat = dims.width + CGFloat(count - 1) * (dims.width + preferredStep)
        let cappedWidth = min(originalWidth, 240)
        return AnyView(
            fan
                .frame(width: originalWidth, height: dims.height)
                .rotationEffect(rotation)
                // After 90° rotation, the fan's intrinsic width becomes
                // the slot's height. Match the frame to that swap so the
                // surrounding VStack reserves the right space.
                .frame(width: dims.height, height: cappedWidth)
        )
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
                .minimumScaleFactor(0.7)
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

    /// Render one card back per card the opponent really holds — the count
    /// is the truth, not a "5+" approximation. The fan adapts its overlap
    /// to fit the available column width so even a 10-card hand stays
    /// inside the seat slot without bleeding into the next opponent.
    private var fan: some View {
        let count = seat.hand.count
        let dims = CardView.Size.compact.dimensions
        return GeometryReader { geo in
            let available = max(0, geo.size.width)
            let totalCardWidth = dims.width
            // Each subsequent card adds `step` to the row's overall width.
            // Step is negative when cards overlap; the floor keeps a
            // hand-suggestion overlap even when there's plenty of room.
            let maxStepForFit: CGFloat = count > 1
                ? (available - totalCardWidth) / CGFloat(count - 1)
                : 0
            let preferred: CGFloat = -dims.width * 0.40
            let lowerBound: CGFloat = -dims.width * 0.78
            let step = max(lowerBound, min(preferred, maxStepForFit))
            HStack(spacing: step) {
                ForEach(0..<count, id: \.self) { index in
                    CardView(
                        card: .hidden,
                        size: .compact,
                        region: .hand(seat: seat.player),
                        indexInRow: index
                    )
                }
            }
            .frame(width: available, alignment: .center)
        }
        .frame(height: count == 0 ? 0 : dims.height)
    }
}
