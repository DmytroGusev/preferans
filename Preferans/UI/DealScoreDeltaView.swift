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

    var id: PlayerID { player }
}

enum DealScoreDeltaPresentation {
    static func rows(
        from delta: ScoreDelta,
        players: [PlayerID]
    ) -> [DealScoreDeltaRow] {
        players.map { player in
            let whistsOut = delta.whists[player]?.values.reduce(0, +) ?? 0
            let whistsIn = delta.whists.values.reduce(0) { total, entries in
                total + (entries[player] ?? 0)
            }
            return DealScoreDeltaRow(
                player: player,
                pool: delta.pool[player] ?? 0,
                mountain: delta.mountain[player] ?? 0,
                whistsIn: whistsIn,
                whistsOut: whistsOut
            )
        }
    }

    static func balanceDelta(
        for row: DealScoreDeltaRow,
        rules: PreferansRules
    ) -> Int {
        row.pool * rules.poolPointWhistValue
            - row.mountain * rules.mountainPointWhistValue
            + row.whistsIn
            - row.whistsOut
    }
}

/// A deal-scoped score explanation. Regular-width iPad surfaces get one card
/// per player in a grid; compact iPhone surfaces keep the same information in
/// a single readable column so the summary does not become a tiny table.
struct DealScoreDeltaView: View {
    let scoreDelta: ScoreDelta
    let players: [PlayerID]
    let rules: PreferansRules
    let displayName: (PlayerID) -> String

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var rows: [DealScoreDeltaRow] {
        DealScoreDeltaPresentation.rows(from: scoreDelta, players: players)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Score recorded")
                .font(.caption.weight(.bold))
                .foregroundStyle(TableTheme.goldBright)
                .textCase(.uppercase)
                .tracking(1.1)

            if horizontalSizeClass == .regular {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(rows) { row in
                        playerDeltaCard(row)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(rows) { row in
                        playerDeltaRow(row)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.dealScoreDelta)
    }

    private func playerDeltaCard(_ row: DealScoreDeltaRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(displayName(row.player))
                .font(.caption.weight(.semibold))
                .foregroundStyle(TableTheme.inkCream)
                .lineLimit(1)
            metricRow(row)
            whistDetail(row)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: TableTheme.Radius.xs, style: .continuous))
    }

    private func playerDeltaRow(_ row: DealScoreDeltaRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(displayName(row.player))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TableTheme.inkCream)
                    .lineLimit(1)
                Spacer(minLength: 4)
                metricValue("Pool", row.pool, tint: TableTheme.goldBright)
                metricValue("Mtn", row.mountain, tint: row.mountain == 0 ? TableTheme.inkCreamSoft : .red)
                metricValue(
                    "Bal",
                    DealScoreDeltaPresentation.balanceDelta(for: row, rules: rules),
                    tint: balanceColor(for: row)
                )
            }
            whistDetail(row)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: TableTheme.Radius.xs, style: .continuous))
    }

    private func metricRow(_ row: DealScoreDeltaRow) -> some View {
        HStack(spacing: 6) {
            metricValue("Pool", row.pool, tint: TableTheme.goldBright)
            metricValue("Mtn", row.mountain, tint: row.mountain == 0 ? TableTheme.inkCreamSoft : .red)
            metricValue(
                "Bal",
                DealScoreDeltaPresentation.balanceDelta(for: row, rules: rules),
                tint: balanceColor(for: row)
            )
        }
    }

    private func metricValue(_ title: LocalizedStringKey, _ value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(TableTheme.inkCreamSoft)
            Text(signed(value))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func whistDetail(_ row: DealScoreDeltaRow) -> some View {
        if row.whistsIn != 0 || row.whistsOut != 0 {
            Text("Whists in \(signed(row.whistsIn)) · out \(signed(row.whistsOut))")
                .font(.caption2)
                .foregroundStyle(TableTheme.inkCreamSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func balanceColor(for row: DealScoreDeltaRow) -> Color {
        let delta = DealScoreDeltaPresentation.balanceDelta(for: row, rules: rules)
        if delta > 0 { return TableTheme.goldBright }
        if delta < 0 { return .red }
        return TableTheme.inkCreamSoft
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}
