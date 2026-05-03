import SwiftUI
import PreferansEngine

/// Inline game-over panel rendered on the felt at match end. Replaces the
/// auto-presented modal sheet so the overflow menu (and the rest of the
/// felt) stays accessible — the user can review the standings and still
/// hop into the scoresheet without dismissing anything first.
public struct GameOverCard: View {
    public var summary: MatchSummary
    public var onRematch: (() -> Void)?
    public var onLeaveTable: (() -> Void)?

    public init(
        summary: MatchSummary,
        onRematch: (() -> Void)? = nil,
        onLeaveTable: (() -> Void)? = nil
    ) {
        self.summary = summary
        self.onRematch = onRematch
        self.onLeaveTable = onLeaveTable
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Game over")
                    .font(.headline.bold())
                    .foregroundStyle(TableTheme.goldBright)
                    .accessibilityIdentifier(UIIdentifiers.gameOverTitle)
                if let winner = summary.standings.first {
                    Text("\(winner.player.rawValue) takes the pulka")
                        .font(.subheadline.bold())
                        .foregroundStyle(TableTheme.inkCream)
                        .accessibilityLabel("\(AccessibilityStrings.gameOverWinnerPrefix)\(winner.player.rawValue)")
                        .accessibilityIdentifier(UIIdentifiers.gameOverWinner)
                    Text("Match won")
                        .font(.caption2)
                        .foregroundStyle(TableTheme.inkCreamSoft)
                }
                Text("\(summary.dealsPlayed) completed \(summary.dealsPlayed == 1 ? "deal" : "deals")")
                    .font(.caption)
                    .foregroundStyle(TableTheme.inkCreamSoft)
                    .accessibilityLabel("\(AccessibilityStrings.completedDealsPrefix)\(summary.dealsPlayed)")
                    .accessibilityIdentifier(UIIdentifiers.gameOverDealsPlayed)
            }

            standingsTable

            if onRematch != nil || onLeaveTable != nil {
                ctaRow
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: TableTheme.Radius.md, style: .continuous)
                .fill(TableTheme.surfaceFill(.card))
        )
        .overlay(
            RoundedRectangle(cornerRadius: TableTheme.Radius.md, style: .continuous)
                .strokeBorder(TableTheme.surfaceBorder(.card), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.Panel.gameOver.rawValue)
    }

    private var ctaRow: some View {
        HStack(spacing: 8) {
            if let onLeaveTable {
                Button {
                    onLeaveTable()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Lobby")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.feltSecondary)
                .accessibilityIdentifier(UIIdentifiers.buttonBackToLobby)
            }
            if let onRematch {
                Button {
                    onRematch()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Rematch")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.feltPrimary)
                .accessibilityIdentifier(UIIdentifiers.buttonRematch)
            }
        }
        .padding(.top, 4)
    }

    private var standingsTable: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Text("")
                    .frame(width: 18, alignment: .leading)
                Text("")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Pool")
                    .frame(width: 40, alignment: .trailing)
                Text("Mtn")
                    .frame(width: 40, alignment: .trailing)
                Text("Bal")
                    .frame(width: 50, alignment: .trailing)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(TableTheme.inkCreamSoft)
            ForEach(Array(summary.standings.enumerated()), id: \.offset) { index, standing in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(TableTheme.inkCream)
                        .frame(width: 18, alignment: .leading)
                    Text(standing.player.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TableTheme.inkCream)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier(UIIdentifiers.gameOverStandingPlayer(rank: index + 1))
                    Text("\(standing.pool)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(TableTheme.inkCream)
                        .frame(width: 40, alignment: .trailing)
                        .accessibilityIdentifier(UIIdentifiers.gameOverStandingPool(rank: index + 1))
                    Text("\(standing.mountain)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(TableTheme.inkCream)
                        .frame(width: 40, alignment: .trailing)
                        .accessibilityIdentifier(UIIdentifiers.gameOverStandingMountain(rank: index + 1))
                    Text(ScoreFormatting.balance(standing.balance))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(TableTheme.inkCream)
                        .frame(width: 50, alignment: .trailing)
                        .accessibilityIdentifier(UIIdentifiers.gameOverStandingBalance(rank: index + 1))
                }
            }
        }
    }
}
