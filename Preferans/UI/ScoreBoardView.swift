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
                headerRow
                ForEach(score.players, id: \.self) { player in
                    scoreRow(player: player)
                }
            }
            .font(.caption)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier(UIIdentifiers.Panel.score.rawValue)
    }

    private var headerRow: some View {
        HStack(spacing: 14) {
            Text("Player").frame(minWidth: 72, alignment: .leading)
            Text("Pool").frame(minWidth: 38, alignment: .trailing)
            Text("Mountain").frame(minWidth: 64, alignment: .trailing)
            Text("Balance").frame(minWidth: 64, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
    }

    private func scoreRow(player: PlayerID) -> some View {
        HStack(spacing: 14) {
            Text(player.rawValue)
                .frame(minWidth: 72, alignment: .leading)
                .accessibilityIdentifier(UIIdentifiers.scorePlayer(player))
            Text("\(score.pool(for: player))")
                .frame(minWidth: 38, alignment: .trailing)
                .accessibilityIdentifier(UIIdentifiers.scorePool(player))
            Text("\(score.mountain(for: player))")
                .frame(minWidth: 64, alignment: .trailing)
                .accessibilityIdentifier(UIIdentifiers.scoreMountain(player))
            Text(score.balance(for: player).formatted(.number.precision(.fractionLength(1))))
                .frame(minWidth: 64, alignment: .trailing)
                .accessibilityIdentifier(UIIdentifiers.scoreBalance(player))
        }
    }
}
