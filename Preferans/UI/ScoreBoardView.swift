import SwiftUI
import PreferansEngine

/// Traditional preferans pulka, one card per player.
///
/// On paper the pulka is drawn as a triangle (3-player) or square (4-player)
/// with each player owning a corner. Each corner records that player's
/// **Пуля** (bullet — fulfilled-contract points), **Гора** (mountain —
/// penalty points), and the **Висты** that player wrote on each opponent.
/// This view keeps the same four sections (Пуля → Гора → Висты → Баланс)
/// per player, stacked as a list of cards so the form scales to 3 or 4
/// players without rewrapping a tabular layout.
public struct ScoreBoardView: View {
    public var score: ScoreSheet

    public init(score: ScoreSheet) {
        self.score = score
    }

    public var body: some View {
        VStack(spacing: 12) {
            ForEach(score.players, id: \.self) { player in
                playerCard(player: player)
            }
            legend
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.Panel.score.rawValue)
    }

    // MARK: - Per-player card

    private func playerCard(player: PlayerID) -> some View {
        let balance = score.balance(for: player)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(player.rawValue)
                    .font(.title3.bold())
                    .accessibilityIdentifier(UIIdentifiers.scorePlayer(player))
                Spacer()
                balanceBadge(balance: balance, id: UIIdentifiers.scoreBalance(player))
            }
            HStack(alignment: .top, spacing: 14) {
                pulaCell(player: player)
                Divider().frame(height: 44)
                goraCell(player: player)
                Divider().frame(height: 44)
                vistyCell(player: player)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.separator.opacity(0.6), lineWidth: 0.5)
        )
    }

    private func pulaCell(player: PlayerID) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Bullet")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
            Text("\(score.pool(for: player))")
                .font(.title.bold().monospacedDigit())
                .accessibilityIdentifier(UIIdentifiers.scorePool(player))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func goraCell(player: PlayerID) -> some View {
        let value = score.mountain(for: player)
        return VStack(alignment: .leading, spacing: 2) {
            Text("Mountain")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
            Text("\(value)")
                .font(.title.bold().monospacedDigit())
                .foregroundStyle(value > 0 ? .red : .primary)
                .accessibilityIdentifier(UIIdentifiers.scoreMountain(player))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Per-player whists section: one row per opponent showing the points
    /// this player has written on them. The traditional pulka draws each
    /// pair-wise relationship in the diagonal between two seats; on a
    /// phone we collapse it to "vs Misha 4 / vs Lena 3" inside the
    /// player's own card.
    private func vistyCell(player: PlayerID) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Whists")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.6)
            VStack(alignment: .leading, spacing: 1) {
                ForEach(score.players.filter { $0 != player }, id: \.self) { target in
                    let value = score.whistsWritten(by: player, on: target)
                    HStack(spacing: 4) {
                        Text("vs \(target.rawValue)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(value)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(value > 0 ? .primary : .tertiary)
                            .accessibilityIdentifier(UIIdentifiers.scoreWhists(writer: player, on: target))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func balanceBadge(balance: Double, id: String) -> some View {
        let formatted = ScoreFormatting.balance(balance)
        let color: Color = balance > 0.05 ? .green : (balance < -0.05 ? .red : .secondary)
        return Text(formatted)
            .font(.subheadline.bold().monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityIdentifier(id)
    }

    // MARK: - Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            legendRow(title: "Пуля (bullet)", description: "Points for fulfilled contracts. Higher is better.")
            legendRow(title: "Гора (mountain)", description: "Penalty points. Lower is better.")
            legendRow(title: "Висты (whists)", description: "Whist points each player has written on every opponent.")
            legendRow(title: "Баланс (balance)", description: "Standings — zero-sum across the table.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private func legendRow(title: LocalizedStringKey, description: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(title).fontWeight(.semibold).foregroundStyle(.primary)
            Text(description)
        }
    }
}
