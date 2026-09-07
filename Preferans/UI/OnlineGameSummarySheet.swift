import SwiftUI
import PreferansEngine

// MARK: - Your-games formatting helpers

enum LobbyFormat {
    /// Human label for a variant tag. Unknown tags are title-cased rather than
    /// dropped, so a future variant still reads sensibly before it's mapped.
    static func variantDisplayName(_ raw: String?) -> String {
        switch raw {
        case "odesa": return "Odesa"
        case "wien":  return "Wien"
        case let other?: return other.capitalized
        case nil: return String(localized: "Preferans")
        }
    }

    // Formatters are expensive to construct; shared statics keep the games
    // list from allocating three per row per render. Main-actor isolated
    // because formatters aren't Sendable and every caller is a view body.
    @MainActor private static let fractionalISO: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    @MainActor private static let plainISO = ISO8601DateFormatter()
    @MainActor private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// "2m ago"-style relative time from a worker ISO-8601 timestamp (which
    /// carries fractional seconds), falling back to the plain form.
    @MainActor static func relativeTime(_ iso: String) -> String {
        guard let date = fractionalISO.date(from: iso) ?? plainISO.date(from: iso) else { return "" }
        return relative.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Finished-game result sheet

/// Read-only summary for a finished online game: winner + each seat's final
/// zero-sum balance. "Summaries only" per the lobby spec — no deal replay.
struct OnlineGameSummarySheet: View {
    @Environment(\.tableTheme) private var theme

    let game: OnlineGameSummary
    @Environment(\.dismiss) private var dismiss

    private struct Row: Identifiable {
        let id: PlayerID
        let name: String
        let balance: Double?
        let isBot: Bool
        let isWinner: Bool
    }

    private var rows: [Row] {
        game.peers.map { peer in
            Row(
                id: peer.playerID,
                name: peer.displayName,
                balance: game.result?.finalBalances?[peer.playerID.rawValue],
                isBot: peer.isBotSeat,
                isWinner: game.result?.winner == peer.playerID
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let winner = game.winnerName {
                        HStack(spacing: 10) {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(theme.accentStrong)
                            Text("Won by \(winner)")
                                .font(.headline)
                                .foregroundStyle(theme.textPrimary)
                        }
                    }

                    Text("Final balances")
                        .font(.caption2.weight(.semibold))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(theme.accent)

                    VStack(spacing: 8) {
                        ForEach(rows) { row in
                            HStack(spacing: 10) {
                                Image(systemName: row.isWinner ? "crown.fill" : (row.isBot ? "cpu" : "person.crop.circle.fill"))
                                    .foregroundStyle(row.isWinner ? theme.accentStrong : theme.accent)
                                Text(verbatim: row.name)
                                    .foregroundStyle(theme.textPrimary)
                                Spacer()
                                if let balance = row.balance {
                                    Text(ScoreFormatting.balance(balance))
                                        .font(.headline.monospacedDigit())
                                        .foregroundStyle(
                                            balance > 0.05
                                                ? theme.success
                                                : (balance < -0.05 ? theme.error : theme.textSecondary)
                                        )
                                }
                            }
                            .padding(10)
                            .background(theme.shade.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .feltBackground()
            .navigationTitle(Text("Game result"))
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { dismiss() }) {
                        Text("Done").foregroundStyle(theme.accentStrong)
                    }
                }
            }
        }
    }
}
