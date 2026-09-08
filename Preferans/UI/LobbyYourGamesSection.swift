import SwiftUI
import PreferansEngine

// MARK: - Your games (Continue / History)

/// The lobby's window onto a player's online games. Continue rows resume an
/// in-progress table; History rows open a finished game's result. Hidden
/// entirely until there's something to show (or an account to show nothing
/// for), so a brand-new player isn't greeted by an empty shelf.
struct LobbyYourGamesSection: View {
    @Environment(\.tableTheme) private var theme

    @ObservedObject var viewModel: LobbyViewModel
    @ObservedObject var gameLibrary: OnlineGameLibrary
    let onSelectFinishedGame: (OnlineGameSummary) -> Void

    @ViewBuilder
    var body: some View {
        if !gameLibrary.inProgress.isEmpty || !gameLibrary.finished.isEmpty {
            onlinePanel(title: "Your games", icon: "clock.arrow.circlepath") {
                yourGamesRefreshRow
                if !gameLibrary.inProgress.isEmpty {
                    yourGamesSubhead("Continue")
                    VStack(spacing: 8) {
                        ForEach(gameLibrary.inProgress) { continueRow($0) }
                    }
                }
                if !gameLibrary.finished.isEmpty {
                    yourGamesSubhead("Finished")
                    VStack(spacing: 8) {
                        ForEach(gameLibrary.finished) { historyRow($0) }
                    }
                }
                if let error = gameLibrary.loadError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(theme.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(UIIdentifiers.onlineGamesSection)
        } else if gameLibrary.isLoading && !gameLibrary.hasLoaded {
            onlinePanel(title: "Your games", icon: "clock.arrow.circlepath") {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading your games…")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(UIIdentifiers.onlineGamesSection)
        } else if gameLibrary.hasLoaded, viewModel.currentOnlineAccountID != nil {
            Text("Games you start or join show up here, so you can pick up where you left off.")
                .font(.footnote)
                .foregroundStyle(theme.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(UIIdentifiers.onlineGamesEmpty)
        }
    }

    private var yourGamesRefreshRow: some View {
        HStack {
            Spacer()
            Button {
                Task { await gameLibrary.refresh(sessionToken: viewModel.onlineAccountSessionToken) }
            } label: {
                Group {
                    if gameLibrary.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.body.weight(.semibold))
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.accent)
            .disabled(gameLibrary.isLoading)
            .accessibilityLabel("Refresh your games")
            .accessibilityIdentifier(UIIdentifiers.onlineGamesRefresh)
        }
    }

    private func yourGamesSubhead(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .tracking(1.0)
            .textCase(.uppercase)
            .foregroundStyle(theme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func continueRow(_ game: OnlineGameSummary) -> some View {
        Button {
            viewModel.resumeCloudflareOnlineRoom(game)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(theme.accentStrong)
                VStack(alignment: .leading, spacing: 2) {
                    Text(continueTitle(game))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(continueSubtitle(game))
                        .font(.caption2)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if viewModel.isOnlineRoomLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(theme.textMuted)
                }
            }
            .padding(10)
            .background(theme.shade.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isOnlineRoomLoading)
        .accessibilityIdentifier(UIIdentifiers.onlineGameResume(roomCode: game.roomCode))
        .contextMenu {
            Button(role: .destructive) {
                Task {
                    await viewModel.abandonOnlineGame(game)
                    gameLibrary.removeLocally(roomCode: game.roomCode)
                }
            } label: {
                Label("Abandon game", systemImage: "trash")
            }
        }
    }

    private func historyRow(_ game: OnlineGameSummary) -> some View {
        Button {
            onSelectFinishedGame(game)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "flag.checkered")
                    .font(.title3)
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(historyTitle(game))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(historySubtitle(game))
                        .font(.caption2)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(theme.textMuted)
            }
            .padding(10)
            .background(theme.shade.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(UIIdentifiers.onlineGameHistory(roomCode: game.roomCode))
    }

    private func continueTitle(_ game: OnlineGameSummary) -> String {
        let variant = LobbyFormat.variantDisplayName(game.variant)
        if game.status == .lobby {
            return variant + " · " + String(localized: "Waiting to start")
        }
        if let deal = game.dealNumber {
            return variant + " · " + String(localized: "Deal \(deal)")
        }
        return variant
    }

    private func continueSubtitle(_ game: OnlineGameSummary) -> String {
        var parts: [String] = []
        let names = game.opponents.map(\.displayName)
        if !names.isEmpty {
            parts.append(String(localized: "with \(names.joined(separator: ", "))"))
        }
        if game.botCount == 1 {
            parts.append(String(localized: "1 bot"))
        } else if game.botCount > 1 {
            parts.append(String(localized: "\(game.botCount) bots"))
        }
        parts.append(LobbyFormat.relativeTime(game.updatedAt))
        return parts.joined(separator: " · ")
    }

    private func historyTitle(_ game: OnlineGameSummary) -> String {
        if let winner = game.winnerName {
            return String(localized: "Won by \(winner)")
        }
        return String(localized: "Finished")
    }

    private func historySubtitle(_ game: OnlineGameSummary) -> String {
        LobbyFormat.variantDisplayName(game.variant) + " · " + LobbyFormat.relativeTime(game.updatedAt)
    }
}

/// Shared panel chrome for the lobby's online sections ("Your games" and the
/// online setup card panels).
@MainActor
func onlinePanel<Content: View>(
    title: LocalizedStringKey,
    icon: String,
    @ViewBuilder content: () -> Content
) -> some View {
    OnlinePanel(title: title, icon: icon, content: content())
}

private struct OnlinePanel<Content: View>: View {
    @Environment(\.tableTheme) private var theme
    let title: LocalizedStringKey
    let icon: String
    let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .textCase(.uppercase)
            } icon: {
                Image(systemName: icon)
            }
            .foregroundStyle(theme.accent)
            content
        }
        .padding(14)
        .feltSurface(.card, radius: TableTheme.Radius.sm)
    }
}
