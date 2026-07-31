import Dependencies
import SwiftUI
import PreferansEngine

/// Transient toast pinned to the felt's optical center. Fires whenever the
/// most recent banner-worthy action changes, fades after a short hold so
/// it doesn't camp on top of the trick area. The persistent per-seat badge
/// (`OpponentSeatView` / viewer name plate) handles "what did X do?"
/// look-up; this view handles "something just happened — look here".
public struct CenterActionBanner: View {
    public var action: RecentAction?
    public var insight: BotDecisionExplanation?
    public var displayName: (PlayerID) -> String

    /// How long the toast stays at full opacity before fading. The user's
    /// eyes need ~0.3s to land on it; 1.4s gives them time to read without
    /// hiding the trick area for too long.
    public var holdDuration: Duration = .milliseconds(1400)

    public init(
        action: RecentAction?,
        insight: BotDecisionExplanation? = nil,
        displayName: @escaping (PlayerID) -> String,
        holdDuration: Duration = .milliseconds(1400)
    ) {
        self.action = action
        self.insight = insight
        self.displayName = displayName
        self.holdDuration = holdDuration
    }

    @State private var current: RecentAction?
    @State private var dismissTask: Task<Void, Never>?

    public var body: some View {
        ZStack {
            if let current {
                pill(for: current)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.92).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                    .id(current.id)
            }
        }
        .animation(.spring(duration: 0.28, bounce: 0.18), value: current?.id)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(UIIdentifiers.actionBanner)
        .onChange(of: action?.id) { _, _ in handle(action) }
        .onAppear { handle(action) }
        // Without this the auto-dismiss task outlives the banner: harmless in
        // effect (it only clears @State), but it keeps a sleeping task alive
        // past the view's lifetime.
        .onDisappear { dismissTask?.cancel() }
    }

    private func pill(for action: RecentAction) -> some View {
        VStack(alignment: .leading, spacing: matchingInsight(for: action) == nil ? 0 : 7) {
            HStack(spacing: 8) {
                Text(displayName(action.player))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(TableTheme.inkCream)
                    .lineLimit(1)
                Text("·")
                    .font(.headline)
                    .foregroundStyle(TableTheme.inkCreamDim)
                action.label.glyph(emphasis: .banner)
                    .font(.title3.weight(.bold))
            }

            if let insight = matchingInsight(for: action) {
                Divider().overlay(TableTheme.gold.opacity(0.28))
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(TableTheme.goldBright)
                    Text(insight.rationale.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(TableTheme.inkCreamSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier(UIIdentifiers.botInsightBanner)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.68))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(TableTheme.gold.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 12, y: 4)
        .frame(maxWidth: 340)
    }

    private func handle(_ next: RecentAction?) {
        guard let next else {
            dismissTask?.cancel()
            current = nil
            return
        }
        if current?.id == next.id { return }
        current = next
        dismissTask?.cancel()
        let hold: Duration = matchingInsight(for: next) == nil
            ? holdDuration
            : .milliseconds(2800)
        @Dependency(\.continuousClock) var clock
        dismissTask = Task { @MainActor [clock] in
            try? await clock.sleep(for: hold)
            if Task.isCancelled { return }
            if current?.id == next.id {
                withAnimation(.easeOut(duration: 0.32)) {
                    current = nil
                }
            }
        }
    }

    private func matchingInsight(for action: RecentAction) -> BotDecisionExplanation? {
        guard let insight,
              insight.actor == action.player,
              insight.rationale.category == action.label.botDecisionCategory else {
            return nil
        }
        return insight
    }
}

private extension RecentAction.Label {
    var botDecisionCategory: BotDecisionCategory {
        switch self {
        case .bid, .pass:
            return .auction
        case .declared, .withoutThree:
            return .contract
        case .discarded:
            return .discard
        case .whist, .halfWhist, .whistPass:
            return .whist
        case .defenderMode:
            return .defenderMode
        }
    }
}
