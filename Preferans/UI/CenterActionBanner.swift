import SwiftUI
import PreferansEngine

/// Transient toast pinned to the felt's optical center. Fires whenever the
/// most recent banner-worthy action changes, fades after a short hold so
/// it doesn't camp on top of the trick area. The persistent per-seat badge
/// (`OpponentSeatView` / viewer name plate) handles "what did X do?"
/// look-up; this view handles "something just happened — look here".
public struct CenterActionBanner: View {
    public var action: RecentAction?
    public var displayName: (PlayerID) -> String

    /// How long the toast stays at full opacity before fading. The user's
    /// eyes need ~0.3s to land on it; 1.4s gives them time to read without
    /// hiding the trick area for too long.
    public var holdDuration: Duration = .milliseconds(1400)

    public init(
        action: RecentAction?,
        displayName: @escaping (PlayerID) -> String,
        holdDuration: Duration = .milliseconds(1400)
    ) {
        self.action = action
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
    }

    private func pill(for action: RecentAction) -> some View {
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
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(Color.black.opacity(0.62))
        )
        .overlay(
            Capsule().strokeBorder(TableTheme.gold.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 12, y: 4)
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
        let hold = holdDuration
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: hold)
            if Task.isCancelled { return }
            if current?.id == next.id {
                withAnimation(.easeOut(duration: 0.32)) {
                    current = nil
                }
            }
        }
    }
}
