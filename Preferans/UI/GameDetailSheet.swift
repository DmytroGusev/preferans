import SwiftUI
import PreferansEngine

enum GameSheetDestination: String, Identifiable {
    case score
    case log
    case rules
    case settings
    case lastTrick

    var id: String { rawValue }
}

/// Owns the modal surfaces reachable from the game header. Keeping their
/// navigation stacks and dismissal chrome outside `ProjectionGameScreen`
/// leaves the main screen responsible for table layout and interaction state.
struct GameDetailSheet: View {
    @Environment(\.tableTheme) private var theme

    let destination: GameSheetDestination
    let projection: PlayerGameProjection
    let activityEntries: [ActivityLogEntry]
    let botInsights: [BotDecisionExplanation]
    let onDismiss: () -> Void

    @ViewBuilder
    var body: some View {
        switch destination {
        case .score:
            scoreSheet
        case .log:
            ActivityLogSheet(
                entries: activityEntries,
                botInsights: botInsights,
                displayName: projection.displayName(for:),
                onDone: onDismiss
            )
        case .rules:
            ConventionLegendSheet(rules: projection.rules, match: projection.match)
        case .settings:
            SettingsScreen()
        case .lastTrick:
            lastTrickSheet
        }
    }

    private var scoreSheet: some View {
        NavigationStack {
            ScrollView {
                ScoreBoardView(
                    score: projection.score,
                    rules: projection.rules,
                    displayName: projection.displayName(for:)
                )
                    .padding()
            }
            .feltBackground()
            .navigationTitle("Scoresheet")
            .themeNavigationChrome()
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    dismissButton
                }
            }
        }
    }

    private var lastTrickSheet: some View {
        NavigationStack {
            Group {
                if let trick = projection.lastCompletedTrick {
                    LastTrickView(projection: projection, trick: trick)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 20)
                } else {
                    Text("Last trick")
                        .font(.headline)
                        .foregroundStyle(theme.textPrimary)
                        .padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .feltBackground()
            .navigationTitle("Last trick")
            .themeNavigationChrome()
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    dismissButton
                }
            }
        }
    }

    private var dismissButton: some View {
        Button("Done", action: onDismiss)
            .accessibilityIdentifier(UIIdentifiers.buttonDismissSheet)
    }
}
