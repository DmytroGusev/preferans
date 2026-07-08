import SwiftUI
import PreferansEngine

// MARK: - Deal-summary card

extension TableView {
    /// Rich centered card shown when a deal has just been scored. Replaces
    /// the empty "Deal complete" placeholder with the outcome headline,
    /// per-player trick tally, and a prominent "Next deal" CTA so the user
    /// has something to look at and a clear action without dismissing a
    /// modal sheet.
    func dealSummaryCard(result: DealResult) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text("Deal complete")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TableTheme.goldBright)
                    .tracking(1.4)
                    .textCase(.uppercase)
                Localized.dealResultHeadline(result, in: projection)
                    .font(.headline)
                    .foregroundStyle(TableTheme.inkCream)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier(UIIdentifiers.dealResultKind)
                Text(UIIdentifiers.encode(result.kind))
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
            }
            trickTallyGrid(result: result)
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
                    .frame(maxWidth: 220)
                }
                .buttonStyle(.feltPrimary)
                .accessibilityIdentifier(UIIdentifiers.buttonStartDeal)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(dealSummaryBackground)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
                .frame(maxWidth: 220)
            }
            .buttonStyle(.feltSecondary)
            .accessibilityIdentifier("dealResult.initialHands.toggle")

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
                .foregroundStyle(player == projection.viewer ? TableTheme.goldBright : TableTheme.inkCreamSoft)
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
        .accessibilityIdentifier("dealResult.initialHand.\(player.rawValue)")
    }

    private func openingHandRows(_ cards: [Card]) -> [[Card]] {
        let sorted = cards.sortedForTableDisplay(order: cardSuitOrder)
        guard sorted.count > 5 else { return [sorted] }
        return [
            Array(sorted.prefix(5)),
            Array(sorted.dropFirst(5))
        ]
    }

    private var dealSummaryBackground: some View {
        RoundedRectangle(cornerRadius: TableTheme.Radius.md, style: .continuous)
            .fill(TableTheme.surfaceFill(.card))
            .overlay(
                RoundedRectangle(cornerRadius: TableTheme.Radius.md, style: .continuous)
                    .strokeBorder(TableTheme.surfaceBorder(.card), lineWidth: 1)
            )
    }

    /// Compact tricks-per-active-player grid. Sitting-out seats are excluded
    /// (they took zero tricks by definition); the declarer is highlighted in
    /// gold so the user can see at a glance whether the contract was met.
    private func trickTallyGrid(result: DealResult) -> some View {
        let players = result.activePlayers
        let declarer = declarer(for: result)
        return HStack(spacing: 8) {
            ForEach(players, id: \.self) { player in
                let isDeclarer = player == declarer
                VStack(spacing: 3) {
                    Text(projection.displayName(for: player))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isDeclarer ? TableTheme.goldBright : TableTheme.inkCream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(result.trickCounts[player] ?? 0)")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(isDeclarer ? TableTheme.goldBright : TableTheme.inkCream)
                        .accessibilityIdentifier(UIIdentifiers.seatTrickCount(player))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: TableTheme.Radius.xs, style: .continuous)
                        .fill(Color.black.opacity(isDeclarer ? 0.32 : 0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: TableTheme.Radius.xs, style: .continuous)
                        .strokeBorder(
                            isDeclarer ? TableTheme.goldBright.opacity(0.55) : TableTheme.inkCream.opacity(0.06),
                            lineWidth: isDeclarer ? 1 : 0.5
                        )
                )
            }
        }
    }

    private func declarer(for result: DealResult) -> PlayerID? {
        switch result.kind {
        case let .game(declarer, _, _):           return declarer
        case let .misere(declarer):               return declarer
        case let .halfWhist(declarer, _, _):      return declarer
        case let .withoutThree(declarer, _):      return declarer
        case .passedOut, .allPass:                return nil
        }
    }
}
