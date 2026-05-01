import SwiftUI
import PreferansEngine

public struct ProjectionGameScreen: View {
    public var projection: PlayerGameProjection
    public var eventLog: [String]
    public var onSend: (PreferansAction) -> Void

    @State private var selectedDiscard: Set<Card> = []

    public init(projection: PlayerGameProjection, eventLog: [String] = [], onSend: @escaping (PreferansAction) -> Void) {
        self.projection = projection
        self.eventLog = eventLog
        self.onSend = onSend
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                actionPanel
                currentTrick
                talonAndDiscard
                hands
                ScoreBoardView(score: projection.score)
                eventPanel
            }
            .padding()
        }
        .navigationTitle("Preferans")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(projection.phase.title)
                .font(.title.bold())
            Text(projection.message)
                .foregroundStyle(.secondary)
            Text("You are: \(displayName(for: projection.viewer))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if projection.legal.canStartDeal {
                Button("Start Deal") {
                    onSend(.startDeal(dealer: nil, deck: nil))
                }
                .buttonStyle(.borderedProminent)
            }

            if !projection.legal.bidCalls.isEmpty {
                Text("Bid")
                    .font(.headline)
                WrappingButtons(items: projection.legal.bidCalls.map { $0.description }) { index in
                    let call = projection.legal.bidCalls[index]
                    onSend(.bid(player: projection.viewer, call: call))
                }
            }

            if projection.legal.canDiscard {
                Text("Select exactly two cards to discard")
                    .font(.headline)
                CardRowView(
                    cards: discardCandidates,
                    selectedCards: selectedDiscard,
                    onTap: toggleDiscardSelection
                )
                Button("Discard selected") {
                    onSend(.discard(player: projection.viewer, cards: Array(selectedDiscard)))
                    selectedDiscard.removeAll()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedDiscard.count != 2)
            }

            if !projection.legal.contractOptions.isEmpty {
                Text("Declare contract")
                    .font(.headline)
                WrappingButtons(items: projection.legal.contractOptions.map { $0.description }) { index in
                    onSend(.declareContract(player: projection.viewer, contract: projection.legal.contractOptions[index]))
                }
            }

            if !projection.legal.whistCalls.isEmpty {
                Text("Whist")
                    .font(.headline)
                WrappingButtons(items: projection.legal.whistCalls.map { $0.description }) { index in
                    onSend(.whist(player: projection.viewer, call: projection.legal.whistCalls[index]))
                }
            }

            if !projection.legal.defenderModes.isEmpty {
                Text("Defender mode")
                    .font(.headline)
                HStack {
                    Button("Closed") { onSend(.chooseDefenderMode(player: projection.viewer, mode: .closed)) }
                    Button("Open") { onSend(.chooseDefenderMode(player: projection.viewer, mode: .open)) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var currentTrick: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current trick")
                .font(.headline)
            if projection.currentTrick.isEmpty {
                Text("No cards on table")
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    ForEach(Array(projection.currentTrick.enumerated()), id: \.offset) { _, play in
                        VStack {
                            CardView(card: .known(play.card))
                            Text(displayName(for: play.player))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text("Completed tricks: \(projection.completedTrickCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var talonAndDiscard: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading) {
                Text("Talon")
                    .font(.headline)
                CardRowView(cards: projection.talon)
            }
            VStack(alignment: .leading) {
                Text("Discard")
                    .font(.headline)
                CardRowView(cards: projection.discard)
            }
        }
    }

    private var hands: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Table")
                .font(.headline)
            ForEach(projection.seats) { seat in
                PlayerHandView(
                    seat: seat,
                    playableCards: seat.player == projection.viewer ? Set(projection.legal.playableCards) : [],
                    onCardTap: { card in
                        guard seat.player == projection.viewer, projection.legal.playableCards.contains(card) else { return }
                        onSend(.playCard(player: projection.viewer, card: card))
                    }
                )
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var eventPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Log")
                .font(.headline)
            ForEach(Array(eventLog.suffix(12).enumerated()), id: \.offset) { _, event in
                Text(event)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var discardCandidates: [ProjectedCard] {
        guard let ownSeat = projection.seats.first(where: { $0.player == projection.viewer }) else { return [] }
        return ownSeat.hand + projection.talon
    }

    private func toggleDiscardSelection(_ card: Card) {
        if selectedDiscard.contains(card) {
            selectedDiscard.remove(card)
        } else if selectedDiscard.count < 2 {
            selectedDiscard.insert(card)
        }
    }

    private func displayName(for player: PlayerID) -> String {
        projection.identities.first { $0.playerID == player }?.displayName ?? player.rawValue
    }
}

private struct WrappingButtons: View {
    var items: [String]
    var onTap: (Int) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items.indices, id: \.self) { index in
                Button(items[index]) { onTap(index) }
                    .buttonStyle(.bordered)
            }
        }
    }
}
