import SwiftUI
import PreferansEngine

public struct ScoreBoardView: View {
    public var score: ScoreSheet

    public init(score: ScoreSheet) {
        self.score = score
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Score")
                .font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                scoreRow("Player", "Pool", "Mountain", "Balance")
                    .font(.caption.weight(.semibold))
                ForEach(score.players, id: \.self) { player in
                    scoreRow(
                        player.rawValue,
                        "\(score.pool(for: player))",
                        "\(score.mountain(for: player))",
                        score.balance(for: player).formatted(.number.precision(.fractionLength(1)))
                    )
                }
            }
            .font(.caption)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func scoreRow(_ player: String, _ pool: String, _ mountain: String, _ balance: String) -> some View {
        HStack(spacing: 14) {
            Text(player).frame(minWidth: 72, alignment: .leading)
            Text(pool).frame(minWidth: 38, alignment: .trailing)
            Text(mountain).frame(minWidth: 64, alignment: .trailing)
            Text(balance).frame(minWidth: 64, alignment: .trailing)
        }
    }
}
