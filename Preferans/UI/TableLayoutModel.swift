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
        case compactHidden
    }

    public var bounds: CGSize

    public init(bounds: CGSize) {
        self.bounds = bounds
    }

    /// True when at least one active opponent has a revealed (face-up)
    /// hand — misère, open whist, etc. Open seats need more vertical
    /// room for taller, suit-grouped fans, so the play area shrinks to
    /// give them headroom.
    public var hasOpenOpponent: Bool {
        // The model doesn't carry the seat list directly; callers pass
        // it in via `opponentSlots`. Open-aware sizing keys off the
        // SeatProjection embedded in each `OpponentSlot`. We re-derive
        // it on demand inside `playAreaSize` / `playAreaPosition` only
        // when callers ask via `playArea(for:)`.
        false
    }

    public var playAreaSize: CGSize {
        playArea(for: []).size
    }

    public var playAreaPosition: CGPoint {
        playArea(for: []).position
    }

    public var bannerPosition: CGPoint {
        CGPoint(x: bounds.width * 0.5, y: bounds.height * 0.50)
    }

    /// Returns the play-area frame for the current opponents. When at
    /// least one opponent has an open hand the play area shrinks and
    /// drifts down so the taller fan above doesn't overlap the trick.
    public func playArea(for opponents: [SeatProjection]) -> (size: CGSize, position: CGPoint) {
        let isAnyOpen = opponents.contains(where: Self.isOpen)
        let heightFactor: CGFloat = isAnyOpen ? 0.50 : 0.62
        let centerY: CGFloat = isAnyOpen ? 0.68 : 0.62
        return (
            size: CGSize(
                width: max(0, bounds.width * 0.86),
                height: max(0, bounds.height * heightFactor)
            ),
            position: CGPoint(x: bounds.width * 0.5, y: bounds.height * centerY)
        )
    }

    public func opponentSlots(opponents: [SeatProjection]) -> [OpponentSlot] {
        switch opponents.count {
        case 1:
            return [
                OpponentSlot(
                    seat: opponents[0],
                    position: CGPoint(x: 0.5, y: openY(opponents[0], base: 0.16)),
                    orientation: .top,
                    kind: slotKind(for: opponents[0], among: opponents, default: .topWide)
                )
            ]
        case 2:
            let firstOpen = Self.isOpen(opponents[0])
            let secondOpen = Self.isOpen(opponents[1])
            if firstOpen != secondOpen {
                return [
                    OpponentSlot(
                        seat: opponents[0],
                        position: CGPoint(
                            x: firstOpen ? 0.38 : 0.20,
                            y: firstOpen ? 0.30 : 0.18
                        ),
                        orientation: .top,
                        kind: slotKind(for: opponents[0], among: opponents, default: .topNarrow)
                    ),
                    OpponentSlot(
                        seat: opponents[1],
                        position: CGPoint(
                            x: secondOpen ? 0.62 : 0.80,
                            y: secondOpen ? 0.30 : 0.18
                        ),
                        orientation: .top,
                        kind: slotKind(for: opponents[1], among: opponents, default: .topNarrow)
                    ),
                ]
            }
            return [
                OpponentSlot(
                    seat: opponents[0],
                    position: CGPoint(x: 0.25, y: openY(opponents[0], base: 0.18)),
                    orientation: .top,
                    kind: slotKind(for: opponents[0], among: opponents, default: .topNarrow)
                ),
                OpponentSlot(
                    seat: opponents[1],
                    position: CGPoint(x: 0.75, y: openY(opponents[1], base: 0.18)),
                    orientation: .top,
                    kind: slotKind(for: opponents[1], among: opponents, default: .topNarrow)
                ),
            ]
        case 3:
            return [
                OpponentSlot(
                    seat: opponents[0],
                    position: CGPoint(x: 0.18, y: openY(opponents[0], base: 0.26)),
                    orientation: .left,
                    kind: slotKind(for: opponents[0], among: opponents, default: .topNarrow)
                ),
                OpponentSlot(
                    seat: opponents[1],
                    position: CGPoint(x: 0.50, y: openY(opponents[1], base: 0.10)),
                    orientation: .top,
                    kind: slotKind(for: opponents[1], among: opponents, default: .topNarrow)
                ),
                OpponentSlot(
                    seat: opponents[2],
                    position: CGPoint(x: 0.82, y: openY(opponents[2], base: 0.26)),
                    orientation: .right,
                    kind: slotKind(for: opponents[2], among: opponents, default: .topNarrow)
                ),
            ]
        default:
            return opponents.enumerated().map { index, seat in
                let x = (CGFloat(index) + 1) / CGFloat(opponents.count + 1)
                return OpponentSlot(
                    seat: seat,
                    position: CGPoint(x: x, y: openY(seat, base: 0.18)),
                    orientation: .top,
                    kind: slotKind(for: seat, among: opponents, default: .topNarrow)
                )
            }
        }
    }

    public func slotFrameSize(for slot: OpponentSlot) -> CGSize {
        let isOpen = Self.isOpen(slot.seat)
        switch slot.kind {
        case .topWide:
            return CGSize(
                width: min(bounds.width * 0.78, 320),
                height: isOpen ? 230 : 182
            )
        case .topNarrow:
            if isOpen {
                return CGSize(
                    width: min(bounds.width * 0.46, 250),
                    height: 230
                )
            }
            return CGSize(width: min(bounds.width * 0.46, 190), height: 182)
        case .compactHidden:
            return CGSize(
                width: min(bounds.width * 0.30, 124),
                height: 132
            )
        }
    }

    private func slotKind(
        for seat: SeatProjection,
        among opponents: [SeatProjection],
        default defaultKind: SlotKind
    ) -> SlotKind {
        let hasOpenPeer = opponents.contains { $0.player != seat.player && Self.isOpen($0) }
        if hasOpenPeer && !Self.isOpen(seat) {
            return .compactHidden
        }
        return defaultKind
    }

    /// Push an open seat down a touch so its taller fan clears the top
    /// edge. Hidden seats keep their published baseline position.
    private func openY(_ seat: SeatProjection, base: CGFloat) -> CGFloat {
        Self.isOpen(seat) ? max(base, 0.22) : base
    }

    private static func isOpen(_ seat: SeatProjection) -> Bool {
        seat.hand.contains { $0.knownCard != nil }
    }

    /// Opponent order for a viewer-relative table where the viewer's hand
    /// stays at the bottom: first item is the next seat clockwise, then the
    /// order continues around the table.
    public static func clockwiseOpponents(
        players: [PlayerID],
        viewer: PlayerID
    ) -> [PlayerID] {
        guard let viewerIndex = players.firstIndex(of: viewer) else {
            return players.filter { $0 != viewer }
        }
        guard players.count > 1 else { return [] }

        return (1..<players.count).map { offset in
            players[(viewerIndex + offset) % players.count]
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

extension PlayerGameProjection {
    var tableClockwiseOpponentSeats: [SeatProjection] {
        let seatsByPlayer = Dictionary(
            seats.map { ($0.player, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var orderedSeats = TableLayoutModel
            .clockwiseOpponents(players: players, viewer: viewer)
            .compactMap { seatsByPlayer[$0] }
        var seen = Set(orderedSeats.map(\.player))

        for seat in seats where seat.player != viewer && !seen.contains(seat.player) {
            orderedSeats.append(seat)
            seen.insert(seat.player)
        }

        return orderedSeats
    }

    var tableClockwiseAuctionSeats: [SeatProjection] {
        let opponents = tableClockwiseOpponentSeats.filter { $0.role != .sittingOut }
        guard let viewerSeat = seats.first(where: {
            $0.player == viewer && $0.role != .sittingOut
        }) else {
            return opponents
        }

        guard opponents.count == 2 else {
            return [viewerSeat] + opponents
        }

        return [opponents[0], viewerSeat, opponents[1]]
    }
}
