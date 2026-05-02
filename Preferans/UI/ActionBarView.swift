import SwiftUI
import PreferansEngine

/// Compact, context-sensitive action bar that sits above the viewer's
/// hand. Renders only the action that is currently legal for the
/// viewer; opponents-turn renders an unobtrusive status row instead.
public struct ActionBarView: View {
    public var projection: PlayerGameProjection
    public var selectedDiscard: Set<Card>
    public var onSend: (PreferansAction) -> Void

    public init(
        projection: PlayerGameProjection,
        selectedDiscard: Set<Card>,
        onSend: @escaping (PreferansAction) -> Void
    ) {
        self.projection = projection
        self.selectedDiscard = selectedDiscard
        self.onSend = onSend
    }

    public var body: some View {
        Group {
            if shouldShowStartDealRow {
                startDealRow
            } else if !projection.legal.bidCalls.isEmpty {
                bidRow
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(UIIdentifiers.Panel.bidding.rawValue)
            } else if !projection.legal.contractOptions.isEmpty {
                contractRow
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(UIIdentifiers.Panel.contract.rawValue)
            } else if !projection.legal.whistCalls.isEmpty {
                whistRow
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(UIIdentifiers.Panel.whist.rawValue)
            } else if !projection.legal.defenderModes.isEmpty {
                defenderRow
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(UIIdentifiers.Panel.defenderMode.rawValue)
            } else if projection.legal.canDiscard {
                discardRow
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(UIIdentifiers.Panel.discard.rawValue)
            } else {
                statusRow
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .feltBand()
    }

    /// Show "Start deal" in the action bar only when the engine is at the
    /// match's pre-first-deal state. Between deals the deal-finished sheet
    /// owns the "advance the match" affordance — surfacing both at once
    /// would render two buttons with the same accessibility identifier
    /// (the action bar's hidden behind the sheet, the sheet's on top),
    /// and XCUITest queries that returned the occluded one would silently
    /// fail to advance the match.
    private var shouldShowStartDealRow: Bool {
        guard projection.legal.canStartDeal else { return false }
        if case .waitingForDeal = projection.phase { return true }
        return false
    }

    private var startDealRow: some View {
        Button {
            onSend(.startDeal(dealer: nil, deck: nil))
        } label: {
            HStack {
                Image(systemName: "play.fill")
                Text("Start deal")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.feltPrimary)
        .accessibilityIdentifier(UIIdentifiers.buttonStartDeal)
    }

    private var bidRow: some View {
        scrollableRow {
            HStack(spacing: 8) {
                ForEach(projection.legal.bidCalls, id: \.self) { call in
                    bidChip(call: call)
                }
            }
        }
    }

    private func bidChip(call: BidCall) -> some View {
        let label = bidLabel(for: call)
        return Button {
            onSend(.bid(player: projection.viewer, call: call))
        } label: {
            HStack(spacing: 4) {
                if let icon = label.icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                if let suit = label.suit {
                    Text(suit.symbol)
                        .foregroundStyle(label.bidColor(for: suit))
                }
                Text(label.text)
                    .fontWeight(.semibold)
            }
        }
        .buttonStyle(label.style)
        .accessibilityIdentifier(UIIdentifiers.bidButton(call))
    }

    private var contractRow: some View {
        let isTotus = isTotusDeclaration
        return scrollableRow {
            HStack(spacing: 8) {
                ForEach(projection.legal.contractOptions, id: \.self) { contract in
                    Button {
                        onSend(.declareContract(player: projection.viewer, contract: contract))
                    } label: {
                        HStack(spacing: 3) {
                            if !isTotus {
                                Text("\(contract.tricks)")
                                    .fontWeight(.bold)
                            }
                            Text(contract.strain.description)
                                .foregroundStyle(strainColor(contract.strain))
                                .fontWeight(.bold)
                        }
                    }
                    .buttonStyle(.feltSecondary)
                    .accessibilityIdentifier(UIIdentifiers.contractButton(contract))
                }
            }
        }
    }

    /// Horizontal scroller with a leading + trailing fade so users get a
    /// visual hint that more options exist beyond the screen edge. Without
    /// this, the bid bar silently clips the rightmost chips.
    @ViewBuilder
    private func scrollableRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content()
                .padding(.horizontal, 2)
        }
        .mask(scrollFadeMask)
    }

    private var scrollFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black, location: 0.04),
                .init(color: .black, location: 0.96),
                .init(color: .clear, location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var whistRow: some View {
        HStack(spacing: 8) {
            ForEach(projection.legal.whistCalls, id: \.self) { call in
                Button { onSend(.whist(player: projection.viewer, call: call)) } label: {
                    Text(call.description)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(call == .whist ? .feltPrimary : .feltDim)
                .accessibilityIdentifier(UIIdentifiers.whistButton(call))
            }
        }
    }

    private var defenderRow: some View {
        HStack(spacing: 8) {
            ForEach(projection.legal.defenderModes, id: \.self) { mode in
                Button {
                    onSend(.chooseDefenderMode(player: projection.viewer, mode: mode))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode == .open ? "eye" : "eye.slash")
                        Text(mode == .open ? "Open" : "Closed")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.feltPrimary)
                .accessibilityIdentifier(UIIdentifiers.defenderModeButton(mode))
            }
        }
    }

    private var discardRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pick 2 to discard")
                    .font(.subheadline.bold())
                    .foregroundStyle(TableTheme.inkCream)
                Text("\(selectedDiscard.count)/2 selected")
                    .font(.caption2)
                    .foregroundStyle(selectedDiscard.count == 2 ? TableTheme.goldBright : TableTheme.inkCreamSoft)
            }
            Spacer()
            Button {
                onSend(.discard(player: projection.viewer, cards: Array(selectedDiscard)))
            } label: {
                Text("Confirm")
                    .fontWeight(.semibold)
            }
            .buttonStyle(FeltButtonStyle(emphasis: selectedDiscard.count == 2 ? .primary : .dim))
            .disabled(selectedDiscard.count != 2)
            .accessibilityIdentifier(UIIdentifiers.buttonDiscardSelected)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            if let actor = currentActorName {
                Image(systemName: "hourglass")
                    .font(.caption)
                    .foregroundStyle(TableTheme.inkCreamSoft)
                Text("Waiting for \(actor)")
                    .font(.subheadline)
                    .foregroundStyle(TableTheme.inkCreamSoft)
            } else {
                Text(projection.message)
                    .font(.subheadline)
                    .foregroundStyle(TableTheme.inkCreamSoft)
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private struct BidLabel {
        enum Kind { case pass, game, misere, totus }
        var text: String
        var suit: Suit?
        var icon: String?
        var kind: Kind

        var style: FeltButtonStyle {
            switch kind {
            case .pass:   return FeltButtonStyle(emphasis: .dim)
            case .game:   return FeltButtonStyle(emphasis: .secondary)
            case .misere: return FeltButtonStyle(emphasis: .secondary, tint: TableTheme.goldBright)
            case .totus:  return FeltButtonStyle(emphasis: .primary, tint: TableTheme.goldBright)
            }
        }

        /// Suit pip color tuned for the felt — reds stay red, blacks are
        /// rendered cream so they remain legible on the dark pill.
        func bidColor(for suit: Suit) -> Color {
            switch suit {
            case .hearts, .diamonds:
                return Color(red: 0.95, green: 0.45, blue: 0.42)
            case .spades, .clubs:
                return TableTheme.inkCream
            }
        }
    }

    private func bidLabel(for call: BidCall) -> BidLabel {
        switch call {
        case .pass:
            return BidLabel(text: "Pass", suit: nil, icon: "xmark", kind: .pass)
        case let .bid(bid):
            switch bid {
            case let .game(contract):
                return BidLabel(text: "\(contract.tricks)", suit: contract.strain.suit, icon: nil, kind: .game)
            case .misere:
                return BidLabel(text: "Misere", suit: nil, icon: nil, kind: .misere)
            case .totus:
                return BidLabel(text: "Totus", suit: nil, icon: nil, kind: .totus)
            }
        }
    }

    /// Strain color tuned for the felt — hearts/diamonds glow warmer red,
    /// spades/clubs render in cream so they read on the dark contract pill.
    private func strainColor(_ strain: Strain) -> Color {
        guard let suit = strain.suit else { return TableTheme.inkCream }
        switch suit {
        case .hearts, .diamonds: return Color(red: 0.95, green: 0.45, blue: 0.42)
        case .spades, .clubs:    return TableTheme.inkCream
        }
    }

    private var isTotusDeclaration: Bool {
        if case let .awaitingContract(_, finalBid) = projection.phase {
            return finalBid == .totus
        }
        return false
    }

    private var currentActorName: String? {
        projection.seats.first { $0.isCurrentActor && $0.player != projection.viewer }?.displayName
    }
}
