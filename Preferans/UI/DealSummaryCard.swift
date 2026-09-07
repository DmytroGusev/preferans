import SwiftUI
import PreferansEngine

struct DealSummaryLayoutPolicy: Equatable {
    var isRegularWidth: Bool
    var usesAccessibilityText: Bool

    /// A regular iPad can give the result and the score explanation separate
    /// reading columns. Accessibility text sizes keep the compact flow so
    /// the score explanation never gets squeezed into a narrow pane.
    var usesTwoRegionComposition: Bool {
        isRegularWidth && !usesAccessibilityText
    }
}

/// Rich centered card shown when a deal has just been scored. Its disclosure
/// state belongs to this deal-scoped surface, so leaving the phase destroys
/// the state instead of leaking "show opening hands" into a later deal.
struct DealSummaryCard: View {
    @Environment(\.tableTheme) private var theme

    let result: DealResult
    let projection: PlayerGameProjection
    let cardSuitOrder: CardSuitDisplayOrder
    let onAdvance: (() -> Void)?

    @State private var showInitialHands = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Rich centered card shown when a deal has just been scored. Replaces
    /// the empty "Deal complete" placeholder with the outcome headline,
    /// per-player trick tally, and a prominent "Next deal" CTA so the user
    /// has something to look at and a clear action without dismissing a
    /// modal sheet.
    var body: some View {
        Group {
            if layoutPolicy.usesTwoRegionComposition {
                regularLayout
            } else {
                compactLayout
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var layoutPolicy: DealSummaryLayoutPolicy {
        DealSummaryLayoutPolicy(
            isRegularWidth: horizontalSizeClass == .regular,
            usesAccessibilityText: dynamicTypeSize.isAccessibilitySize
        )
    }

    private var compactLayout: some View {
        VStack(spacing: 14) {
            resultColumn
            scoreColumn
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(dealSummaryBackground)
    }

    /// iPad keeps the outcome and the accounting explanation side by side so
    /// the next-deal action remains visible without scrolling past the score
    /// delta or opening-hands disclosure.
    private var regularLayout: some View {
        HStack(alignment: .top, spacing: 22) {
            resultColumn
                .frame(maxWidth: .infinity, alignment: .top)
            scoreColumn
                .frame(maxWidth: 360, alignment: .top)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(dealSummaryBackground)
    }

    private var resultColumn: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text(LocalizedStringKey(result.settlement == nil ? "Deal complete" : "Agreed result"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(theme.accentStrong)
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .accessibilityIdentifier(UIIdentifiers.dealResultStatus)
                Localized.dealResultHeadline(result, in: projection)
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(UIIdentifiers.dealResultKind)
                Text(UIIdentifiers.encode(result.kind))
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            if result.trickCounts.values.contains(where: { $0 > 0 }) {
                trickTallyGrid(result: result)
            }
        }
    }

    private var scoreColumn: some View {
        VStack(spacing: 14) {
            DealScoreDeltaView(
                scoreDelta: result.scoreDelta,
                players: projection.players,
                rules: projection.rules,
                displayName: projection.displayName(for:)
            )
            if let initialHands = result.initialHands, !initialHands.isEmpty {
                openingHandsDisclosure(hands: initialHands, activePlayers: result.activePlayers)
            }
            if let onAdvance, projection.legal.canStartDeal {
                Button {
                    onAdvance()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("Next deal")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 220)
                }
                .buttonStyle(.feltPrimary)
                .accessibilityIdentifier(UIIdentifiers.buttonStartDeal)
            }
        }
    }

    private func openingHandsDisclosure(
        hands: [PlayerID: [Card]],
        activePlayers: [PlayerID]
    ) -> some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showInitialHands.toggle()
                }
            } label: {
                // Two literals, not a ternary: a ternary inside Label() types
                // as String and silently opts the copy out of localization.
                Group {
                    if showInitialHands {
                        Label("Hide opening hands", systemImage: "eye.slash.fill")
                    } else {
                        Label("Show opening hands", systemImage: "eye.fill")
                    }
                }
                .font(.caption.weight(.semibold))
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 220)
            }
            .buttonStyle(.feltSecondary)
            .accessibilityIdentifier(UIIdentifiers.dealInitialHandsToggle)

            if showInitialHands {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(activePlayers, id: \.self) { player in
                            openingHandRow(player: player, cards: hands[player] ?? [])
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 250)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func openingHandRow(player: PlayerID, cards: [Card]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(projection.displayName(for: player))
                .font(.caption2.weight(.bold))
                .foregroundStyle(player == projection.viewer ? theme.accentStrong : theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(openingHandRows(cards).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 4) {
                        ForEach(row, id: \.self) { card in
                            CardView(
                                card: .known(card),
                                size: .compact,
                                region: .hand(seat: player)
                            )
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.dealInitialHand(player))
    }

    private func openingHandRows(_ cards: [Card]) -> [[Card]] {
        DealSummaryPresentation.openingHandRows(cards, order: cardSuitOrder)
    }

    private var dealSummaryBackground: some View {
        RoundedRectangle(cornerRadius: TableTheme.Radius.md, style: .continuous)
            .fill(theme.surfaceFill(.card))
            .overlay(
                RoundedRectangle(cornerRadius: TableTheme.Radius.md, style: .continuous)
                    .strokeBorder(theme.surfaceBorder(.card), lineWidth: 1)
            )
    }

    /// Compact tricks-per-taker grid. A sitting-out fourth player is normally
    /// excluded, but joins the tally after a classic raspasy because either
    /// dealer-owned talon card can win an opening trick.
    private func trickTallyGrid(result: DealResult) -> some View {
        let players = projection.seats
            .map(\.player)
            .filter { result.trickCounts[$0] != nil }
        let declarer = DealSummaryPresentation.declarer(in: result.kind)
        let columns = players.count > 3
            ? [GridItem(.adaptive(minimum: 112), spacing: 8)]
            : players.map { _ in GridItem(.flexible(), spacing: 8) }
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(players, id: \.self) { player in
                let isDeclarer = player == declarer
                VStack(spacing: 3) {
                    Text(projection.displayName(for: player))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isDeclarer ? theme.accentStrong : theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(result.trickCounts[player] ?? 0)")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(isDeclarer ? theme.accentStrong : theme.textPrimary)
                        .accessibilityIdentifier(UIIdentifiers.seatTrickCount(player))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: TableTheme.Radius.xs, style: .continuous)
                        .fill(theme.shade.opacity(isDeclarer ? 0.32 : 0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: TableTheme.Radius.xs, style: .continuous)
                        .strokeBorder(
                            isDeclarer ? theme.accentStrong.opacity(0.55) : theme.textPrimary.opacity(0.06),
                            lineWidth: isDeclarer ? 1 : 0.5
                        )
                )
            }
        }
    }
}

enum DealSummaryPresentation {
    static func declarer(in kind: DealResultKind) -> PlayerID? {
        switch kind {
        case let .game(declarer, _, _):           return declarer
        case let .misere(declarer):               return declarer
        case let .halfWhist(declarer, _, _):      return declarer
        case let .withoutThree(declarer, _):      return declarer
        case .passedOut, .allPass:                return nil
        }
    }

    static func openingHandRows(
        _ cards: [Card],
        order: CardSuitDisplayOrder
    ) -> [[Card]] {
        let sorted = cards.sortedForTableDisplay(order: order)
        guard sorted.count > 5 else { return [sorted] }
        return [
            Array(sorted.prefix(5)),
            Array(sorted.dropFirst(5)),
        ]
    }
}
