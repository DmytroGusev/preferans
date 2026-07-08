import SwiftUI
import PreferansEngine

struct ActivityLogSheet: View {
    var entries: [ActivityLogEntry]
    var onDone: () -> Void

    private var newestFirst: [ActivityLogEntry] {
        Array(entries.reversed())
    }

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ActivityLogEmptyState()
                } else {
                    List {
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
                                .foregroundStyle(TableTheme.inkCreamSoft)
                                .textCase(.uppercase)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .environment(\.defaultMinListRowHeight, 1)
                }
            }
            .background {
                TableTheme.feltGradient
                    .ignoresSafeArea()
            }
            .navigationTitle("Activity log")
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

private struct ActivityLogRow: View {
    var entry: ActivityLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(entry.kind.tint.opacity(0.18))
                Image(systemName: entry.kind.iconName)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(entry.kind.tint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: entry.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(TableTheme.inkCream)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = entry.detail {
                    Text(verbatim: detail)
                        .font(.caption)
                        .foregroundStyle(TableTheme.inkCreamSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(verbatim: entry.kind.label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(entry.kind.tint)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(entry.kind.tint.opacity(0.13), in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .feltSurface(.chip, radius: TableTheme.Radius.xs)
        .accessibilityElement(children: .combine)
    }
}

private struct ActivityLogEmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "scroll")
                .font(.title2.weight(.semibold))
                .foregroundStyle(TableTheme.goldBright)
                .frame(width: 48, height: 48)
                .background(TableTheme.gold.opacity(0.14), in: Circle())
            Text("No activity yet")
                .font(.headline.weight(.semibold))
                .foregroundStyle(TableTheme.inkCream)
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

    var tint: Color {
        switch self {
        case .deal:       return TableTheme.inkCreamSoft
        case .auction:    return TableTheme.goldBright
        case .contract:   return Color(red: 0.58, green: 0.82, blue: 0.96)
        case .defense:    return Color(red: 0.72, green: 0.86, blue: 0.62)
        case .play:       return Color(red: 0.96, green: 0.78, blue: 0.54)
        case .settlement: return Color(red: 0.84, green: 0.72, blue: 0.96)
        case .scoring:    return TableTheme.gold
        }
    }
}
