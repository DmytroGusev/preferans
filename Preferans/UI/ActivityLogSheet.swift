import SwiftUI
import PreferansEngine

struct ActivityLogSheet: View {
    @Environment(\.tableTheme) private var theme

    var entries: [ActivityLogEntry]
    var botInsights: [BotDecisionExplanation]
    var displayName: (PlayerID) -> String
    var onDone: () -> Void

    init(
        entries: [ActivityLogEntry],
        botInsights: [BotDecisionExplanation] = [],
        displayName: @escaping (PlayerID) -> String = { $0.rawValue },
        onDone: @escaping () -> Void
    ) {
        self.entries = entries
        self.botInsights = botInsights
        self.displayName = displayName
        self.onDone = onDone
    }

    private var newestFirst: [ActivityLogEntry] {
        Array(entries.reversed())
    }

    private var newestBotInsights: [BotDecisionExplanation] {
        Array(botInsights.suffix(12).reversed())
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty && botInsights.isEmpty {
                    ActivityLogEmptyState()
                } else {
                    List {
                        if !newestBotInsights.isEmpty {
                            Section {
                                ForEach(Array(newestBotInsights.enumerated()), id: \.offset) { index, insight in
                                    BotInsightRow(
                                        insight: insight,
                                        displayName: displayName(insight.actor)
                                    )
                                    .listRowInsets(.init(top: 6, leading: 14, bottom: 6, trailing: 14))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .accessibilityIdentifier(UIIdentifiers.botInsightEntry(index: index))
                                }
                            } header: {
                                Text("bot.insight.section")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(theme.accent)
                                    .textCase(.uppercase)
                            }
                        }

                        if !entries.isEmpty {
                            Section {
                                ForEach(newestFirst) { entry in
                                    ActivityLogRow(entry: entry)
                                        .listRowInsets(.init(top: 6, leading: 14, bottom: 6, trailing: 14))
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                        .accessibilityIdentifier(UIIdentifiers.eventLogEntry(index: entry.id))
                                }
                            } header: {
                                Text("Latest activity")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(theme.textSecondary)
                                    .textCase(.uppercase)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.defaultMinListRowHeight, 1)
                }
            }
            .background {
                theme.gradient
                    .ignoresSafeArea()
            }
            .navigationTitle("Activity log")
            .themeNavigationChrome()
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") { onDone() }
                        .accessibilityIdentifier(UIIdentifiers.buttonDismissSheet)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(UIIdentifiers.Panel.eventLog.rawValue)
        }
    }
}

private struct BotInsightRow: View {
    @Environment(\.tableTheme) private var theme

    var insight: BotDecisionExplanation
    var displayName: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(theme.accent.opacity(0.18))
                Image(systemName: "sparkles")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(theme.accentStrong)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(verbatim: displayName)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("·")
                        .foregroundStyle(theme.textMuted)
                    Text(insight.profile.temperament.label)
                    Text(insight.profile.difficulty.label)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.accent)
                .lineLimit(1)

                Text(insight.rationale.label)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .feltSurface(.chip, radius: TableTheme.Radius.xs)
        .accessibilityElement(children: .combine)
    }
}

private struct ActivityLogRow: View {
    @Environment(\.tableTheme) private var theme

    var entry: ActivityLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(entry.kind.tint(in: theme).opacity(0.18))
                Image(systemName: entry.kind.iconName)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(entry.kind.tint(in: theme))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: entry.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = entry.detail {
                    Text(verbatim: detail)
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(verbatim: entry.kind.label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(entry.kind.tint(in: theme))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(entry.kind.tint(in: theme).opacity(0.13), in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .feltSurface(.chip, radius: TableTheme.Radius.xs)
        .accessibilityElement(children: .combine)
    }
}

private struct ActivityLogEmptyState: View {
    @Environment(\.tableTheme) private var theme

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "scroll")
                .font(.title2.weight(.semibold))
                .foregroundStyle(theme.accentStrong)
                .frame(width: 48, height: 48)
                .background(theme.accent.opacity(0.14), in: Circle())
            Text("No activity yet")
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension ActivityLogEntry.Kind {
    var iconName: String {
        switch self {
        case .deal:       return "rectangle.stack.fill"
        case .auction:    return "hand.raised.fill"
        case .contract:   return "checkmark.seal.fill"
        case .defense:    return "shield.fill"
        case .play:       return "suit.club.fill"
        case .settlement: return "text.bubble.fill"
        case .scoring:    return "chart.bar.fill"
        }
    }

    func tint(in theme: TableTheme) -> Color {
        switch self {
        case .deal:       return theme.textSecondary
        case .auction:    return theme.accentStrong
        case .contract:   return theme.accent
        case .defense:    return theme.success
        case .play:       return theme.warning
        case .settlement: return theme.accent
        case .scoring:    return theme.accent
        }
    }
}
