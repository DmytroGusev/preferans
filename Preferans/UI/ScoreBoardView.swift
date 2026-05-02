import SwiftUI
import PreferansEngine

/// Standard preferans pulka (scoresheet) form.
///
/// The traditional pulka has three sections per player — Bullet (Пуля) for
/// fulfilled-contract points, Mountain (Гора) for penalty points, and a Whists
/// (Висты) matrix recording how many whist points each player has written on
/// each opponent. The radial triangle layout used on paper doesn't translate
/// well to a phone, so this view uses a tabular form with the same three
/// sections explicit and labelled.
public struct ScoreBoardView: View {
    public var score: ScoreSheet

    public init(score: ScoreSheet) {
        self.score = score
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 14) {
                bulletSection
                Divider().opacity(0.4)
                mountainSection
                Divider().opacity(0.4)
                whistsSection
                Divider().opacity(0.4)
                balanceSection
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

            legend
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.Panel.score.rawValue)
    }

    // MARK: - Sections

    private var bulletSection: some View {
        section(title: "Bullet", subtitle: "Пуля") {
            playerColumns { player in
                scoreCell(
                    "\(score.pool(for: player))",
                    id: UIIdentifiers.scorePool(player),
                    weight: .semibold
                )
            }
        }
    }

    private var mountainSection: some View {
        section(title: "Mountain", subtitle: "Гора") {
            playerColumns { player in
                scoreCell(
                    "\(score.mountain(for: player))",
                    id: UIIdentifiers.scoreMountain(player),
                    color: score.mountain(for: player) > 0 ? .red : .primary
                )
            }
        }
    }

    private var whistsSection: some View {
        section(title: "Whists", subtitle: "Висты") {
            VStack(spacing: 6) {
                whistHeaderRow
                ForEach(score.players, id: \.self) { writer in
                    whistRow(writer: writer)
                }
            }
        }
    }

    private var balanceSection: some View {
        section(title: "Balance", subtitle: nil) {
            playerColumns { player in
                scoreCell(
                    formatBalance(score.balance(for: player)),
                    id: UIIdentifiers.scoreBalance(player),
                    weight: .bold,
                    color: balanceColor(score.balance(for: player))
                )
            }
        }
    }

    // MARK: - Layout helpers

    private func section<Content: View>(
        title: String,
        subtitle: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            content()
        }
    }

    private func playerColumns<Content: View>(
        @ViewBuilder cell: @escaping (PlayerID) -> Content
    ) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(score.players, id: \.self) { player in
                    Text(player.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier(UIIdentifiers.scorePlayer(player))
                }
            }
            HStack(spacing: 0) {
                ForEach(score.players, id: \.self) { player in
                    cell(player)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func scoreCell(
        _ text: String,
        id: String,
        weight: Font.Weight = .medium,
        color: Color = .primary
    ) -> some View {
        Text(text)
            .font(.body.monospacedDigit().weight(weight))
            .foregroundStyle(color)
            .accessibilityIdentifier(id)
    }

    // MARK: - Whists matrix

    private var whistHeaderRow: some View {
        HStack(spacing: 0) {
            Text("on →")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 56, alignment: .leading)
            ForEach(score.players, id: \.self) { target in
                Text(target.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func whistRow(writer: PlayerID) -> some View {
        HStack(spacing: 0) {
            Text(writer.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            ForEach(score.players, id: \.self) { target in
                whistCell(writer: writer, target: target)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func whistCell(writer: PlayerID, target: PlayerID) -> some View {
        if writer == target {
            Text("—")
                .font(.body.monospacedDigit())
                .foregroundStyle(.tertiary)
        } else {
            let value = score.whistsWritten(by: writer, on: target)
            Text("\(value)")
                .font(.body.monospacedDigit())
                .foregroundStyle(value > 0 ? .primary : .tertiary)
                .accessibilityIdentifier(UIIdentifiers.scoreWhists(writer: writer, on: target))
        }
    }

    // MARK: - Formatting

    private func formatBalance(_ value: Double) -> String {
        let formatted = value.formatted(.number.precision(.fractionLength(1)))
        return value > 0 ? "+\(formatted)" : formatted
    }

    private func balanceColor(_ value: Double) -> Color {
        if value > 0.05 { return .green }
        if value < -0.05 { return .red }
        return .primary
    }

    // MARK: - Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            legendRow(title: "Bullet (Пуля)", description: "Points for fulfilled contracts")
            legendRow(title: "Mountain (Гора)", description: "Penalty points; lower is better")
            legendRow(title: "Whists (Висты)", description: "Whist points written on each opponent")
            legendRow(title: "Balance", description: "Net settlement")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private func legendRow(title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(title).fontWeight(.semibold).foregroundStyle(.primary)
            Text(description)
        }
    }
}
