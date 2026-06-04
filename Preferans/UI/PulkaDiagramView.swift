import SwiftUI
import PreferansEngine

/// Traditional preferans pulka drawn as the classic *конверт* (envelope):
/// a triangle (3 players) or square (4 players) with the seats at the
/// corners, the dividing diagonals/cevians running through a central
/// **Пуля** hub, each corner carrying that player's bullet (Пуля) and
/// mountain (Гора) plus running balance, and the whists each pair shares
/// written along the edge between them. Opposite corners are players
/// sitting across the table, so the figure mirrors real seating and
/// experienced players "read" the table from the corners faster than from
/// a list.
public struct PulkaDiagramView: View {
    public var score: ScoreSheet
    /// Resolves a seat's `PlayerID` (a compass id like `east` online) to the
    /// name the player actually sees. Threaded from the projection so the
    /// diagram never leaks raw seat ids.
    public var displayName: (PlayerID) -> String

    public init(score: ScoreSheet, displayName: @escaping (PlayerID) -> String) {
        self.score = score
        self.displayName = displayName
    }

    private enum Layout { case triangle, square }

    /// An undirected edge between two seats, shared by the pair of players
    /// who write whists on each other along it.
    private struct Edge: Hashable { let a: Int; let b: Int }

    public var body: some View {
        let players = Array(score.players.prefix(4))
        let layout: Layout = players.count >= 4 ? .square : .triangle
        return GeometryReader { geo in
            let bounds = geo.size
            let corners = cornerPoints(for: layout, in: bounds)
            let center = centroid(of: corners)
            ZStack {
                figure(corners: corners, center: center, isSquare: layout == .square)
                ForEach(edges(for: layout), id: \.self) { edge in
                    whistMarker(a: players[edge.a], b: players[edge.b])
                        .position(midpoint(corners[edge.a], corners[edge.b]))
                }
                pulyaHub()
                    .position(center)
                ForEach(Array(players.enumerated()), id: \.offset) { idx, player in
                    cornerCard(player: player)
                        .position(corners[idx])
                }
            }
        }
        .frame(height: layout == .square ? 300 : 240)
    }

    // MARK: - Geometry

    private func cornerPoints(for layout: Layout, in bounds: CGSize) -> [CGPoint] {
        let norm: [(CGFloat, CGFloat)]
        switch layout {
        case .triangle:
            norm = [(0.50, 0.16), (0.16, 0.84), (0.84, 0.84)]
        case .square:
            // Upright square so the two diagonals cross as the iconic
            // envelope "X". Insets leave room for the corner cards to
            // straddle each corner without clipping at sidebar widths.
            norm = [(0.20, 0.17), (0.80, 0.17), (0.80, 0.83), (0.20, 0.83)]
        }
        return norm.map { CGPoint(x: bounds.width * $0.0, y: bounds.height * $0.1) }
    }

    private func centroid(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let n = CGFloat(points.count)
        return CGPoint(x: points.map(\.x).reduce(0, +) / n,
                       y: points.map(\.y).reduce(0, +) / n)
    }

    private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    /// Edges between adjacent seats. For the triangle every pair is an edge;
    /// for the square the four sides cover the neighbouring pairs while the
    /// two diagonals (drawn, but not labelled) join the across-table pairs —
    /// their whists live in the per-player cards below.
    private func edges(for layout: Layout) -> [Edge] {
        switch layout {
        case .triangle:
            return [Edge(a: 0, b: 1), Edge(a: 1, b: 2), Edge(a: 2, b: 0)]
        case .square:
            return [Edge(a: 0, b: 1), Edge(a: 1, b: 2), Edge(a: 2, b: 3), Edge(a: 3, b: 0)]
        }
    }

    // MARK: - Figure

    private func figure(corners: [CGPoint], center: CGPoint, isSquare: Bool) -> some View {
        ZStack {
            Path { path in
                guard let first = corners.first else { return }
                path.move(to: first)
                for point in corners.dropFirst() { path.addLine(to: point) }
                path.closeSubpath()
            }
            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)

            // The interior dividers: diagonals for the square, cevians to the
            // centre for the triangle. Faint and dashed so they read as the
            // scoresheet's structure rather than competing with the numbers.
            Path { path in
                if isSquare, corners.count >= 4 {
                    path.move(to: corners[0]); path.addLine(to: corners[2])
                    path.move(to: corners[1]); path.addLine(to: corners[3])
                } else {
                    for corner in corners { path.move(to: corner); path.addLine(to: center) }
                }
            }
            .stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
        }
    }

    private func pulyaHub() -> some View {
        Text("Пуля")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.separator.opacity(0.5), lineWidth: 0.5))
    }

    @ViewBuilder
    private func whistMarker(a: PlayerID, b: PlayerID) -> some View {
        let total = score.whistsWritten(by: a, on: b) + score.whistsWritten(by: b, on: a)
        if total > 0 {
            Text("\(total)")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.separator.opacity(0.4), lineWidth: 0.5))
        }
    }

    // MARK: - Corner card

    private func cornerCard(player: PlayerID) -> some View {
        let balance = score.balance(for: player)
        let balanceColor: Color = balance > 0.05 ? .green : (balance < -0.05 ? .red : .secondary)
        return VStack(spacing: 3) {
            Text(displayName(player))
                .font(.subheadline.bold())
                .lineLimit(1)
            HStack(spacing: 8) {
                statCell(label: "П", value: "\(score.pool(for: player))", tint: .primary)
                statCell(label: "Г", value: "\(score.mountain(for: player))",
                         tint: score.mountain(for: player) > 0 ? .red : .primary)
            }
            Text(ScoreFormatting.balance(balance))
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(balanceColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(balanceColor.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        )
        .frame(maxWidth: 124)
    }

    private func statCell(label: String, value: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
        }
    }
}
