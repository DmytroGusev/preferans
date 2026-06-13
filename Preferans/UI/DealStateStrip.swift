import SwiftUI
import PreferansEngine

/// Compact, persistent deal-state band. The strip keeps the table state in
/// sentence form instead of a row of competing pills: primary contract or
/// phase on the first line, then one readable trick-count line below.
public struct DealStateStrip: View {
    public var projection: PlayerGameProjection

    public init(projection: PlayerGameProjection) {
        self.projection = projection
    }

    public var body: some View {
        if shouldRender {
            // One line only: contract / phase on the left, contract progress
            // on the right. Per-seat trick counts used to live on a second
            // line here, but they duplicated the seat pills (opponents) and
            // the viewer plate, so the eye read the same tallies three times.
            primaryRow
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .feltSurface(.chip, radius: TableTheme.Radius.sm)
                .padding(.horizontal, 8)
        }
    }

    private var shouldRender: Bool {
        switch projection.phase {
        case .waitingForDeal, .bidding, .awaitingContract, .dealFinished, .gameOver:
            return false
        default:
            return true
        }
    }

    private var primaryRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            primarySummary
            Spacer(minLength: 8)
            trailingSummary
        }
    }

    @ViewBuilder
    private var primarySummary: some View {
        if let summary = projection.activeContractSummary() {
            HStack(spacing: 6) {
                Text(projection.displayName(for: summary.declarer))
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(TableTheme.inkCream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                bidGlyph(bid: summary.bid)
                    .font(.subheadline.weight(.heavy))
                    .fixedSize()
            }
        } else if let (player, bid) = highestBid() {
            HStack(spacing: 6) {
                phaseLabel("Auction")
                Text(projection.displayName(for: player))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TableTheme.inkCream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                bidGlyph(bid: bid)
                    .font(.caption.weight(.bold))
                    .fixedSize()
            }
        } else {
            phaseLabel(Localized.phaseTitle(projection.phase))
        }
    }

    @ViewBuilder
    private var trailingSummary: some View {
        if let progress = contractProgress() {
            HStack(spacing: 4) {
                Text("strip.contract.tricks")
                Text("\(progress.taken)/\(progress.target)")
                    .monospacedDigit()
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(progressColor(progress.state))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
        } else if isTrickPlay {
            HStack(spacing: 4) {
                Text("Trick")
                Text("\(min(10, projection.completedTrickCount + 1))")
                    .monospacedDigit()
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(TableTheme.inkCreamSoft)
            .lineLimit(1)
        } else {
            Localized.statusText(projection)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TableTheme.inkCreamSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private func phaseLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(TableTheme.inkCream)
            .lineLimit(1)
    }

    @ViewBuilder
    private func bidGlyph(bid: ContractBid) -> some View {
        switch bid {
        case let .game(contract):
            HStack(spacing: 1) {
                Text("\(contract.tricks)")
                    .foregroundStyle(TableTheme.inkCream)
                if let suit = contract.strain.suit {
                    Text(suit.symbol)
                        .foregroundStyle(suit.color(on: .felt))
                } else {
                    Text("NT")
                        .foregroundStyle(TableTheme.inkCream)
                }
            }
        case .misere:
            Text("Misère")
                .foregroundStyle(TableTheme.inkCream)
        case .totus:
            Text("Totus")
                .foregroundStyle(TableTheme.inkCream)
        }
    }

    private var isTrickPlay: Bool {
        if case .playing = projection.phase { return true }
        return false
    }

    private func highestBid() -> (PlayerID, ContractBid)? {
        var best: (PlayerID, ContractBid)?
        for call in projection.auction {
            if case let .bid(bid) = call.call {
                if let (_, current) = best {
                    if bid > current { best = (call.player, bid) }
                } else {
                    best = (call.player, bid)
                }
            }
        }
        return best
    }

    private func contractProgress() -> ContractProgress? {
        guard let summary = projection.activeContractSummary(),
              case let .game(contract) = summary.bid else {
            return nil
        }
        let taken = projection.trickCounts[summary.declarer] ?? 0
        let target = contract.tricks
        let remaining = max(0, 10 - projection.completedTrickCount)
        let state: ContractProgress.State
        if taken >= target {
            state = .met
        } else if isTrickPlay, taken + remaining < target {
            state = .behind
        } else {
            state = .live
        }
        return ContractProgress(taken: taken, target: target, state: state)
    }

    private func progressColor(_ state: ContractProgress.State) -> Color {
        switch state {
        // "Met" is good news but it isn't an action — keep it cream so bright
        // gold stays reserved for whose-turn / the viewer's controls.
        case .met:    return TableTheme.inkCream
        case .live:   return TableTheme.inkCream
        case .behind: return Color(red: 1.0, green: 0.55, blue: 0.50)
        }
    }

    private struct ContractProgress {
        var taken: Int
        var target: Int
        var state: State

        enum State {
            case live
            case met
            case behind
        }
    }
}
