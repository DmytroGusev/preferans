import SwiftUI
import PreferansEngine

/// Pulka diagram for 3- and 4-player preferans. Each player owns a
/// corner — triangle for 3, diamond/square for 4 — showing their bullet
/// (Пуля), mountain (Гора) and running balance. Cultural shorthand —
/// experienced players "read" the table state from the corners faster
/// than from a list. Player order follows engine seat order so opposite
/// corners reflect across-the-table seating.
public struct PulkaDiagramView: View {
    public var score: ScoreSheet

    public init(score: ScoreSheet) {
        self.score = score
    }

    public var body: some View {
        let players = Array(score.players.prefix(4))
        let layout = layoutKind(for: players.count)
        return GeometryReader { geo in
            let bounds = geo.size
            ZStack {
                outline(for: layout, in: bounds)
                ForEach(Array(players.enumerated()), id: \.offset) { idx, player in
                    let position = corner(for: idx, layout: layout, in: bounds)
                    cornerCard(player: player)
                        .position(x: position.x, y: position.y)
                }
            }
        }
        .frame(height: layout == .square ? 300 : 220)
    }

    private enum Layout { case triangle, square }

    private func layoutKind(for count: Int) -> Layout {
        count >= 4 ? .square : .triangle
    }

    private func corner(for index: Int, layout: Layout, in bounds: CGSize) -> CGPoint {
        let coords: [(CGFloat, CGFloat)]
        switch layout {
        case .triangle:
            coords = [(0.50, 0.18), (0.18, 0.82), (0.82, 0.82)]
        case .square:
            // Diamond — top, right, bottom, left — so opposite seats sit
            // across the diagram and the corners stay clear of each other.
            coords = [(0.50, 0.12), (0.88, 0.50), (0.50, 0.88), (0.12, 0.50)]
        }
        let i = min(index, coords.count - 1)
        return CGPoint(x: bounds.width * coords[i].0, y: bounds.height * coords[i].1)
    }

    private func outline(for layout: Layout, in bounds: CGSize) -> some View {
        let count = layout == .square ? 4 : 3
        let points = (0..<count).map { corner(for: $0, layout: layout, in: bounds) }
        return Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
        }
        .stroke(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
    }

    private func cornerCard(player: PlayerID) -> some View {
        let balance = score.balance(for: player)
        let balanceColor: Color = balance > 0.05 ? .green : (balance < -0.05 ? .red : .secondary)
        return VStack(spacing: 4) {
            Text(player.rawValue)
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
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator.opacity(0.5), lineWidth: 0.5)
        )
        .frame(maxWidth: 130)
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
