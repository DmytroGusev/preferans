import SwiftUI
import PreferansEngine

/// The score change written by one deal, kept separate from the running
/// scoresheet so the deal summary can explain the result without duplicating
/// scoring arithmetic in SwiftUI.
struct DealScoreDeltaRow: Equatable, Identifiable {
    let player: PlayerID
    let pool: Int
    let mountain: Int
    let whistsIn: Int
    let whistsOut: Int
    let balance: Double

    var id: PlayerID { player }
}

enum DealScoreDeltaPresentation {
    static func rows(
        from delta: ScoreDelta,
        players: [PlayerID],
        rules: PreferansRules
    ) -> [DealScoreDeltaRow] {
        // DealResult already contains the delta after pool closure and aid.
        // Apply it verbatim, then use the same zero-sum calculation as the
        // running scoresheet. Normalization is linear, so these balances are
        // exactly the change from the preceding score, including idle seats.
        var score = ScoreSheet(players: players)
        score.apply(delta, closingAtPoolTarget: .max)
        let balances = score.normalizedBalances(
            poolPointValue: Double(rules.poolPointWhistValue),
            mountainPointValue: Double(rules.mountainPointWhistValue)
        )
        return players.map { player in
            let whistsIn = delta.whists[player]?.values.reduce(0, +) ?? 0
            let whistsOut = delta.whists.values.reduce(0) { total, entries in
                total + (entries[player] ?? 0)
            }
            return DealScoreDeltaRow(
                player: player,
                pool: delta.pool[player] ?? 0,
                mountain: delta.mountain[player] ?? 0,
                whistsIn: whistsIn,
                whistsOut: whistsOut,
                balance: balances[player] ?? 0
            )
        }
    }

}

/// A deal-scoped score explanation. Names and fractional balance changes
/// share one row; the recorded pool, mountain, and whists wrap below them.
struct DealScoreDeltaView: View {
    @Environment(\.tableTheme) private var theme

    let scoreDelta: ScoreDelta
    let players: [PlayerID]
    let rules: PreferansRules
    let displayName: (PlayerID) -> String

    private var rows: [DealScoreDeltaRow] {
        DealScoreDeltaPresentation.rows(from: scoreDelta, players: players, rules: rules)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Score recorded")
                    .fontWeight(.bold)
                    .foregroundStyle(theme.accentStrong)
                Spacer(minLength: 8)
                Text("Balance")
                    .foregroundStyle(theme.textSecondary)
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)

            ForEach(rows) { row in
                playerDeltaRow(row)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.dealScoreDelta)
    }

    private func playerDeltaRow(_ row: DealScoreDeltaRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(displayName(row.player))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(ScoreFormatting.balance(row.balance))
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(balanceColor(for: row))
                    .fixedSize()
                    .accessibilityLabel("Balance")
                    .accessibilityValue(ScoreFormatting.balance(row.balance))
                    .accessibilityIdentifier(UIIdentifiers.dealBalanceDelta(row.player))
            }
            Text("Pool \(signed(row.pool)) · Mountain \(signed(row.mountain))")
                .font(.caption2)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            whistDetail(row)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(theme.shade.opacity(0.16), in: RoundedRectangle(cornerRadius: TableTheme.Radius.xs, style: .continuous))
    }

    @ViewBuilder
    private func whistDetail(_ row: DealScoreDeltaRow) -> some View {
        if row.whistsIn != 0 || row.whistsOut != 0 {
            Text("Whists earned \(signed(row.whistsIn)) · owed \(signed(row.whistsOut))")
                .font(.caption2)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func balanceColor(for row: DealScoreDeltaRow) -> Color {
        let delta = row.balance
        if delta > 0 { return theme.accentStrong }
        if delta < 0 { return theme.error }
        return theme.textSecondary
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}
