import SwiftUI
import PreferansEngine

/// Full scoresheet view, designed to live in a dedicated screen / sheet.
/// Compact pool / mountain / balance per player with clear column headers.
public struct ScoreBoardView: View {
    public var score: ScoreSheet

    public init(score: ScoreSheet) {
        self.score = score
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                headerRow
                Divider()
                ForEach(score.players, id: \.self) { player in
                    scoreRow(player: player)
                    if player != score.players.last {
                        Divider().opacity(0.3)
                    }
                }
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

            legend
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.Panel.score.rawValue)
    }

    private var headerRow: some View {
        HStack {
            Text("Player").frame(maxWidth: .infinity, alignment: .leading)
            Text("Pool").frame(width: 60, alignment: .trailing)
            Text("Mountain").frame(width: 80, alignment: .trailing)
            Text("Balance").frame(width: 70, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func scoreRow(player: PlayerID) -> some View {
        HStack {
            Text(player.rawValue)
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(UIIdentifiers.scorePlayer(player))
            Text("\(score.pool(for: player))")
                .font(.body.monospacedDigit())
                .frame(width: 60, alignment: .trailing)
                .accessibilityIdentifier(UIIdentifiers.scorePool(player))
            Text("\(score.mountain(for: player))")
                .font(.body.monospacedDigit())
                .frame(width: 80, alignment: .trailing)
                .accessibilityIdentifier(UIIdentifiers.scoreMountain(player))
            Text(score.balance(for: player).formatted(.number.precision(.fractionLength(1))))
                .font(.body.monospacedDigit().weight(.semibold))
                .frame(width: 70, alignment: .trailing)
                .accessibilityIdentifier(UIIdentifiers.scoreBalance(player))
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            legendRow(title: "Pool", description: "Points awarded for fulfilled contracts")
            legendRow(title: "Mountain", description: "Penalty points from undertricks and whists")
            legendRow(title: "Balance", description: "Net score, lower mountain is better")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private func legendRow(title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(title)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(description)
        }
    }
}
