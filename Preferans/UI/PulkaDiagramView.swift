import SwiftUI
import PreferansEngine

/// Triangular pulka diagram for 3-player preferans. Each player owns a
/// corner of the triangle showing their bullet (Пуля), mountain (Гора)
/// and running balance. Cultural shorthand — experienced players "read"
/// the table state from the corners faster than from a list. For
/// 4-player tables the parent view falls back to the cards layout; the
/// square-pulka variant is left for a follow-up.
public struct PulkaDiagramView: View {
    public var score: ScoreSheet

    public init(score: ScoreSheet) {
        self.score = score
    }

    public var body: some View {
        let players = Array(score.players.prefix(3))
        return GeometryReader { geo in
            let bounds = geo.size
            ZStack {
                triangleOutline(in: bounds)
                ForEach(Array(players.enumerated()), id: \.offset) { idx, player in
                    let position = corner(for: idx, in: bounds)
                    cornerCard(player: player)
                        .position(x: position.x, y: position.y)
                }
            }
        }
        .frame(height: 220)
    }

    private func corner(for index: Int, in bounds: CGSize) -> CGPoint {
        let xs: [CGFloat] = [0.50, 0.18, 0.82]
        let ys: [CGFloat] = [0.18, 0.82, 0.82]
        let i = min(index, xs.count - 1)
        return CGPoint(x: bounds.width * xs[i], y: bounds.height * ys[i])
    }

    private func triangleOutline(in bounds: CGSize) -> some View {
        let p0 = corner(for: 0, in: bounds)
        let p1 = corner(for: 1, in: bounds)
        let p2 = corner(for: 2, in: bounds)
        return Path { path in
            path.move(to: p0)
            path.addLine(to: p1)
            path.addLine(to: p2)
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
