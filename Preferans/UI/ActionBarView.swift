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
            if projection.legal.canStartDeal {
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
        .background(.regularMaterial)
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
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier(UIIdentifiers.buttonStartDeal)
    }

    private var bidRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(projection.legal.bidCalls, id: \.self) { call in
                    bidChip(call: call)
                }
            }
            .padding(.horizontal, 2)
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
                        .foregroundStyle(suit == .hearts || suit == .diamonds ? .red : .primary)
                }
                Text(label.text)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(label.tint)
        .accessibilityIdentifier(UIIdentifiers.bidButton(call))
    }

    private var contractRow: some View {
        let isTotus = isTotusDeclaration
        return ScrollView(.horizontal, showsIndicators: false) {
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
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(UIIdentifiers.contractButton(contract))
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var whistRow: some View {
        HStack(spacing: 8) {
            ForEach(projection.legal.whistCalls, id: \.self) { call in
                Button { onSend(.whist(player: projection.viewer, call: call)) } label: {
                    Text(call.description)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(call == .whist ? .accentColor : .secondary)
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
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(UIIdentifiers.defenderModeButton(mode))
            }
        }
    }

    private var discardRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pick 2 to discard")
                    .font(.subheadline.bold())
                Text("\(selectedDiscard.count)/2 selected")
                    .font(.caption2)
                    .foregroundStyle(selectedDiscard.count == 2 ? Color.accentColor : .secondary)
            }
            Spacer()
            Button {
                onSend(.discard(player: projection.viewer, cards: Array(selectedDiscard)))
            } label: {
                Text("Confirm")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedDiscard.count != 2)
            .accessibilityIdentifier(UIIdentifiers.buttonDiscardSelected)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            if let actor = currentActorName {
                Image(systemName: "hourglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Waiting for \(actor)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(projection.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private struct BidLabel {
        var text: String
        var suit: Suit?
        var icon: String?
        var tint: Color
    }

    private func bidLabel(for call: BidCall) -> BidLabel {
        switch call {
        case .pass:
            return BidLabel(text: "Pass", suit: nil, icon: "xmark", tint: .secondary)
        case let .bid(bid):
            switch bid {
            case let .game(contract):
                return BidLabel(text: "\(contract.tricks)", suit: contract.strain.suit, icon: nil, tint: .accentColor)
            case .misere:
                return BidLabel(text: "Misere", suit: nil, icon: nil, tint: .purple)
            case .totus:
                return BidLabel(text: "Totus", suit: nil, icon: nil, tint: .orange)
            }
        }
    }

    private func strainColor(_ strain: Strain) -> Color {
        guard let suit = strain.suit else { return .primary }
        return (suit == .hearts || suit == .diamonds) ? .red : .primary
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
