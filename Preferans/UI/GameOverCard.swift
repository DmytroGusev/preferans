import SwiftUI
import PreferansEngine

struct GameOverLayoutPolicy: Equatable {
    var isRegularWidth: Bool
    var usesAccessibilityText: Bool

    /// Regular iPad gets a two-region terminal screen: standings stay in the
    /// reading area while the actions occupy a predictable control column.
    /// Accessibility text sizes keep the compact flow so labels never become
    /// trapped in a narrow tablet column.
    var usesTwoRegionComposition: Bool {
        isRegularWidth && !usesAccessibilityText
    }

}

/// Inline game-over panel rendered on the felt at match end. Replaces the
/// auto-presented modal sheet so the overflow menu (and the rest of the
/// felt) stays accessible — the user can review the standings and still
/// hop into the scoresheet without dismissing anything first.
public struct GameOverCard: View {
    @Environment(\.tableTheme) private var theme

    public var summary: MatchSummary
    /// Resolves a seat's `PlayerID` to the name the player sees, so the
    /// winner line and standings show real names instead of the raw compass
    /// seat ids used online.
    public var displayName: (PlayerID) -> String
    public var onRematch: (() -> Void)?
    public var onLeaveTable: (() -> Void)?

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(
        summary: MatchSummary,
        displayName: @escaping (PlayerID) -> String,
        onRematch: (() -> Void)? = nil,
        onLeaveTable: (() -> Void)? = nil
    ) {
        self.summary = summary
        self.displayName = displayName
        self.onRematch = onRematch
        self.onLeaveTable = onLeaveTable
    }

    public var body: some View {
        Group {
            if layoutPolicy.usesTwoRegionComposition {
                regularLayout
            } else {
                compactLayout
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: TableTheme.Radius.md, style: .continuous)
                .fill(theme.surfaceFill(.card))
        )
        .overlay(
            RoundedRectangle(cornerRadius: TableTheme.Radius.md, style: .continuous)
                .strokeBorder(theme.surfaceBorder(.card), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.Panel.gameOver.rawValue)
    }

    private var layoutPolicy: GameOverLayoutPolicy {
        GameOverLayoutPolicy(
            isRegularWidth: horizontalSizeClass == .regular,
            usesAccessibilityText: dynamicTypeSize.isAccessibilitySize
        )
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            summaryHeader
            standingsTable
            if onRematch != nil || onLeaveTable != nil {
                ctaRow
            }
        }
    }

    /// iPad terminal state gives the result and the actions separate visual
    /// jobs. The standings remain scannable while the vertical CTA column is
    /// reachable without making the score table compete with two wide buttons.
    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                summaryHeader
                standingsTable
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if onRematch != nil || onLeaveTable != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Match complete")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.textSecondary)
                    ctaRow
                }
                .frame(width: 168, alignment: .leading)
            }
        }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Game over")
                .font(.headline.bold())
                .foregroundStyle(theme.accentStrong)
                .accessibilityIdentifier(UIIdentifiers.gameOverTitle)
            if let winner = summary.soleWinner {
                Text("\(displayName(winner)) takes the pulka")
                    .font(.subheadline.bold())
                    .foregroundStyle(theme.textPrimary)
                    .accessibilityIdentifier(UIIdentifiers.gameOverWinner)
            } else if summary.leadingPlayers.count > 1 {
                Text("Shared lead: \(summary.leadingPlayers.map(displayName).joined(separator: ", "))")
                    .font(.subheadline.bold())
                    .foregroundStyle(theme.textPrimary)
                    .accessibilityIdentifier(UIIdentifiers.gameOverWinner)
            }
            Text("\(summary.dealsPlayed) completed deals")
                .font(.caption)
                .foregroundStyle(theme.textSecondary)
                .accessibilityIdentifier(UIIdentifiers.gameOverDealsPlayed)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var ctaRow: some View {
        VStack(spacing: 8) {
            ctaButtons
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var ctaButtons: some View {
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

    private var standingsTable: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text("Standings")
                Spacer(minLength: 8)
                Text("Balance")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(summary.standings.enumerated()), id: \.offset) { index, standing in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(summary.rank(of: standing.player) ?? index + 1)")
                            .foregroundStyle(theme.accentStrong)
                        Text(displayName(standing.player))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier(UIIdentifiers.gameOverStandingPlayer(rank: index + 1))
                        Text(ScoreFormatting.balance(standing.balance))
                            .monospacedDigit()
                            .fixedSize()
                            .accessibilityLabel("Balance")
                            .accessibilityValue(ScoreFormatting.balance(standing.balance))
                            .accessibilityIdentifier(UIIdentifiers.gameOverStandingBalance(rank: index + 1))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) { recordedPoints(standing, index: index) }
                        VStack(alignment: .leading, spacing: 3) { recordedPoints(standing, index: index) }
                    }
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                }
                .padding(10)
                .background(theme.shade.opacity(0.16), in: RoundedRectangle(cornerRadius: TableTheme.Radius.xs))
            }
        }
    }

    @ViewBuilder
    private func recordedPoints(_ standing: MatchSummary.Standing, index: Int) -> some View {
        HStack(spacing: 4) {
            Text("Pool")
            Text("\(standing.pool)")
                .monospacedDigit()
                .accessibilityIdentifier(UIIdentifiers.gameOverStandingPool(rank: index + 1))
        }
        .fixedSize()
        HStack(spacing: 4) {
            Text("Mountain")
            Text("\(standing.mountain)")
                .monospacedDigit()
                .accessibilityIdentifier(UIIdentifiers.gameOverStandingMountain(rank: index + 1))
        }
        .fixedSize()
    }
}
