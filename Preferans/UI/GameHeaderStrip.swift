import SwiftUI
import PreferansEngine

// MARK: - Header strip
//
// Phase and turn information share a flexible column. Frequently used table
// controls stay directly available with full-size touch targets.

extension ProjectionGameScreen {
    var headerStrip: some View {
        HStack(alignment: .center, spacing: 8) {
            phaseChip
            Spacer(minLength: 8)
            // Each icon owns its touch target; labels can wrap alongside it.
            HStack(spacing: 0) {
                if projection.lastCompletedTrick != nil {
                    lastTrickButton
                }
                scoresheetButton
                if onLeaveTable != nil {
                    leaveButton
                }
                overflowMenu
            }
        }
        .alert(
            "Leave this table?",
            isPresented: $showLeaveConfirm
        ) {
            Button("Leave table", role: .destructive) {
                onLeaveTable?()
            }
            Button("Stay", role: .cancel) {}
        } message: {
            Text(leaveTableMessage)
        }
    }

    /// Keep the target independent of the symbol's visual size.
    private func headerIconTarget<Glyph: View>(_ glyph: Glyph) -> some View {
        glyph
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
    }

    private var lastTrickButton: some View {
        Button {
            activeSheet = .lastTrick
        } label: {
            headerIconTarget(
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(theme.accentStrong, theme.shade.opacity(0.30))
                    .font(.title3)
            )
        }
        .accessibilityLabel("Last trick")
        .accessibilityIdentifier(UIIdentifiers.buttonLastTrick)
    }

    /// One-tap exit from the live table. Always reachable so the user is
    /// never trapped — confirms before tearing down the match so a
    /// mistapped exit doesn't lose the deal.
    private var leaveButton: some View {
        Button {
            showLeaveConfirm = true
        } label: {
            headerIconTarget(
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(theme.textPrimary, theme.shade.opacity(0.30))
                    .font(.title3)
            )
        }
        .accessibilityLabel("Leave table")
        .accessibilityIdentifier(UIIdentifiers.buttonLeaveTable)
    }

    /// Surfaces the scoresheet directly in the header instead of burying it
    /// in the overflow menu — it's the most-wanted info during a match.
    private var scoresheetButton: some View {
        Button {
            activeSheet = .score
        } label: {
            headerIconTarget(
                Image(systemName: "tablecells.fill")
                    .foregroundStyle(theme.textPrimary)
                    .font(.subheadline.weight(.semibold))
                    .padding(6)
                    .background(theme.shade.opacity(0.30), in: Capsule())
            )
        }
        .accessibilityLabel("Scoresheet")
        .accessibilityIdentifier(UIIdentifiers.buttonScoreSheet)
    }

    private var phaseChip: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Localized.phaseTitle(projection.phase))
                .font(.caption.weight(.bold))
                // Phase name is orientation, not an action — cream, not gold.
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(UIIdentifiers.phaseTitle)
            if let winner = pendingAdvance?.trickWinner {
                Text("\(projection.displayName(for: winner)) took the trick")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(UIIdentifiers.phaseMessage)
            } else if !shouldShowCenterDealCTA {
                Localized.statusText(projection)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(UIIdentifiers.phaseMessage)
            } else {
                // Idle state: the centered Deal CTA already says everything
                // the message would. Keep the AX node so XCUI tests that
                // sample phase.message in idle still find a label, but make
                // it invisible so the chip stays compact.
                Localized.statusText(projection)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(width: 0, height: 0)
                    .clipped()
                    .opacity(0)
                    .accessibilityIdentifier(UIIdentifiers.phaseMessage)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .feltSurface(.chip, radius: TableTheme.Radius.pill)
    }

    private var overflowMenu: some View {
        SwiftUI.Menu {
            extraMenu

            Button {
                activeSheet = .log
            } label: {
                Label("Activity log", systemImage: "scroll")
            }
            .accessibilityIdentifier(UIIdentifiers.buttonActivityLog)
            Button {
                activeSheet = .rules
            } label: {
                Label("rules.reference.title", systemImage: "book.closed")
            }
            .accessibilityIdentifier(UIIdentifiers.buttonRulesReference)
            Divider()
            Button {
                activeSheet = .settings
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            if onLeaveTable != nil {
                Divider()
                Button(role: .destructive) {
                    showLeaveConfirm = true
                } label: {
                    Label("Leave table", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        } label: {
            headerIconTarget(
                Image(systemName: "ellipsis.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(theme.textPrimary, theme.shade.opacity(0.30))
                    .font(.title3)
            )
            .accessibilityLabel("Menu")
        }
        .accessibilityIdentifier(UIIdentifiers.overflowMenu)
    }
}
