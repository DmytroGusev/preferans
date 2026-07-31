import SwiftUI
import PreferansEngine

// MARK: - Header strip
//
// Replaces both the old phaseStatusBar and the toolbar pill. One row:
// a small phase chip on the left, a single overflow menu on the right.
// Score / event log / settings / View-as all live behind that one
// ellipsis button instead of competing for top-of-screen real estate.

extension ProjectionGameScreen {
    var headerStrip: some View {
        HStack(alignment: .center, spacing: 8) {
            phaseChip
            Spacer(minLength: 8)
            // The icons own their spacing via 40 pt hit frames; extra
            // HStack spacing here would push the phase chip into
            // truncation on compact widths.
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
        .confirmationDialog(
            "Leave this table?",
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button("Leave table", role: .destructive) {
                onLeaveTable?()
            }
            Button("Stay", role: .cancel) {}
        } message: {
            Text("Your current match will be discarded.")
        }
    }

    /// Shared hit-target treatment for the header's icon buttons. The
    /// glyphs render at ~22 pt; without this the tappable area is the
    /// glyph itself (~31 pt), well under the 44 pt HIG minimum. 40 pt is
    /// the compromise that still fits four buttons plus the phase chip on
    /// a compact phone.
    private func headerIconTarget<Glyph: View>(_ glyph: Glyph) -> some View {
        glyph
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
    }

    private var lastTrickButton: some View {
        Button {
            activeSheet = .lastTrick
        } label: {
            headerIconTarget(
                Image(systemName: "arrow.counterclockwise.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(TableTheme.goldBright, Color.black.opacity(0.30))
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
                    .foregroundStyle(TableTheme.inkCream, Color.black.opacity(0.30))
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
                    .foregroundStyle(TableTheme.inkCream)
                    .font(.subheadline.weight(.semibold))
                    .padding(6)
                    .background(Color.black.opacity(0.30), in: Capsule())
            )
        }
        .accessibilityLabel("Scoresheet")
        .accessibilityIdentifier(UIIdentifiers.buttonScoreSheet)
    }

    private var phaseChip: some View {
        HStack(spacing: 6) {
            Text(Localized.phaseTitle(projection.phase))
                .font(.caption.weight(.bold))
                // Phase name is orientation, not an action — cream, not gold.
                .foregroundStyle(TableTheme.inkCream)
                .lineLimit(1)
                .accessibilityIdentifier(UIIdentifiers.phaseTitle)
            if !shouldShowCenterDealCTA {
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(TableTheme.inkCreamDim)
                Localized.statusText(projection)
                    .font(.caption)
                    .foregroundStyle(TableTheme.inkCreamSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
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
                    .foregroundStyle(TableTheme.inkCream, Color.black.opacity(0.30))
                    .font(.title3)
            )
            .accessibilityLabel("Menu")
        }
        .accessibilityIdentifier(UIIdentifiers.overflowMenu)
    }
}
