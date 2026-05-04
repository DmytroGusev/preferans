import SwiftUI
import PreferansEngine

public struct TableLayoutModel: Equatable {
    public struct OpponentSlot: Equatable {
        public var seat: SeatProjection
        public var position: CGPoint
        public var orientation: OpponentSeatView.Orientation
        public var kind: SlotKind
    }

    public enum SlotKind: Equatable {
        case topWide
        case topNarrow
    }

    public var bounds: CGSize

    public init(bounds: CGSize) {
        self.bounds = bounds
    }

    public var playAreaSize: CGSize {
        CGSize(width: max(0, bounds.width * 0.86), height: max(0, bounds.height * 0.62))
    }

    public var playAreaPosition: CGPoint {
        CGPoint(x: bounds.width * 0.5, y: bounds.height * 0.62)
    }

    public var bannerPosition: CGPoint {
        CGPoint(x: bounds.width * 0.5, y: bounds.height * 0.50)
    }

    public func opponentSlots(opponents: [SeatProjection]) -> [OpponentSlot] {
        switch opponents.count {
        case 1:
            return [
                OpponentSlot(
                    seat: opponents[0],
                    position: CGPoint(x: 0.5, y: 0.16),
                    orientation: .top,
                    kind: .topWide
                )
            ]
        case 2:
            return [
                OpponentSlot(
                    seat: opponents[0],
                    position: CGPoint(x: 0.25, y: 0.18),
                    orientation: .top,
                    kind: .topNarrow
                ),
                OpponentSlot(
                    seat: opponents[1],
                    position: CGPoint(x: 0.75, y: 0.18),
                    orientation: .top,
                    kind: .topNarrow
                ),
            ]
        case 3:
            return [
                OpponentSlot(
                    seat: opponents[0],
                    position: CGPoint(x: 0.18, y: 0.26),
                    orientation: .left,
                    kind: .topNarrow
                ),
                OpponentSlot(
                    seat: opponents[1],
                    position: CGPoint(x: 0.50, y: 0.10),
                    orientation: .top,
                    kind: .topNarrow
                ),
                OpponentSlot(
                    seat: opponents[2],
                    position: CGPoint(x: 0.82, y: 0.26),
                    orientation: .right,
                    kind: .topNarrow
                ),
            ]
        default:
            return opponents.enumerated().map { index, seat in
                let x = (CGFloat(index) + 1) / CGFloat(opponents.count + 1)
                return OpponentSlot(seat: seat, position: CGPoint(x: x, y: 0.18), orientation: .top, kind: .topNarrow)
            }
        }
    }

    public func slotFrameSize(for slot: OpponentSlot) -> CGSize {
        switch slot.kind {
        case .topWide:
            return CGSize(width: min(bounds.width * 0.78, 320), height: 182)
        case .topNarrow:
            return CGSize(width: min(bounds.width * 0.46, 190), height: 182)
        }
    }

    public static func trickOffset(
        for player: PlayerID,
        viewer: PlayerID,
        opponents: [PlayerID],
        cardSize: CardView.Size = .standard
    ) -> CGSize {
        let dims = cardSize.dimensions
        let w = dims.width
        let h = dims.height
        if player == viewer { return CGSize(width: 0, height: h * 0.7) }
        switch opponents.count {
        case 1:
            return CGSize(width: 0, height: -h * 0.7)
        case 2:
            let x = w * 1.1
            let y = -h * 0.45
            return player == opponents[0] ? CGSize(width: -x, height: y) : CGSize(width: x, height: y)
        case 3:
            if player == opponents[0] { return CGSize(width: -w * 1.05, height: -h * 0.55) }
            if player == opponents[1] { return CGSize(width: 0, height: -h * 0.85) }
            return CGSize(width: w * 1.05, height: -h * 0.55)
        default:
            return .zero
        }
    }
}
