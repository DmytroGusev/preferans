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
                if case let .gameOver(summary) = projection.phase {
                    gameOverPanel(summary: summary)
                } else {
                    actionPanel
                    if case let .dealFinished(result) = projection.phase {
                        dealFinishedBadge(result: result)
                    }
                    currentTrick
                    talonAndDiscard
                    hands
                }
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
                .accessibilityIdentifier(UIIdentifiers.phaseTitle)
            Text(projection.message)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(UIIdentifiers.phaseMessage)
            Text("You are: \(displayName(for: projection.viewer))")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(UIIdentifiers.viewerLabel)
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
                .accessibilityIdentifier(UIIdentifiers.buttonStartDeal)
            }

            biddingPanel
            discardPanel
            contractPanel
            whistPanel
            defenderModePanel
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var biddingPanel: some View {
        if !projection.legal.bidCalls.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Bid")
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(projection.legal.bidCalls.indices, id: \.self) { index in
                        let call = projection.legal.bidCalls[index]
                        Button(call.description) {
                            onSend(.bid(player: projection.viewer, call: call))
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier(UIIdentifiers.bidButton(call))
                    }
                }
            }
            .accessibilityIdentifier(UIIdentifiers.Panel.bidding.rawValue)
        }
    }

    @ViewBuilder
    private var discardPanel: some View {
        if projection.legal.canDiscard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Select exactly two cards to discard")
                    .font(.headline)
                CardRowView(
                    cards: discardCandidates,
                    selectedCards: selectedDiscard,
                    region: .discardSelect,
                    onTap: toggleDiscardSelection
                )
                Button("Discard selected") {
                    onSend(.discard(player: projection.viewer, cards: Array(selectedDiscard)))
                    selectedDiscard.removeAll()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedDiscard.count != 2)
                .accessibilityIdentifier(UIIdentifiers.buttonDiscardSelected)
            }
            .accessibilityIdentifier(UIIdentifiers.Panel.discard.rawValue)
        }
    }

    @ViewBuilder
    private var contractPanel: some View {
        if !projection.legal.contractOptions.isEmpty {
            let isTotus = isTotusDeclaration
            VStack(alignment: .leading, spacing: 6) {
                Text(isTotus ? "Pick totus strain" : "Declare contract")
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(projection.legal.contractOptions.indices, id: \.self) { index in
                        let contract = projection.legal.contractOptions[index]
                        Button(isTotus ? contract.strain.description : contract.description) {
                            onSend(.declareContract(player: projection.viewer, contract: contract))
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier(UIIdentifiers.contractButton(contract))
                    }
                }
            }
            .accessibilityIdentifier(UIIdentifiers.Panel.contract.rawValue)
        }
    }

    @ViewBuilder
    private var whistPanel: some View {
        if !projection.legal.whistCalls.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Whist")
                    .font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(projection.legal.whistCalls.indices, id: \.self) { index in
                        let call = projection.legal.whistCalls[index]
                        Button(call.description) {
                            onSend(.whist(player: projection.viewer, call: call))
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier(UIIdentifiers.whistButton(call))
                    }
                }
            }
            .accessibilityIdentifier(UIIdentifiers.Panel.whist.rawValue)
        }
    }

    @ViewBuilder
    private var defenderModePanel: some View {
        if !projection.legal.defenderModes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Defender mode")
                    .font(.headline)
                HStack {
                    Button("Closed") { onSend(.chooseDefenderMode(player: projection.viewer, mode: .closed)) }
                        .accessibilityIdentifier(UIIdentifiers.defenderModeButton(.closed))
                    Button("Open") { onSend(.chooseDefenderMode(player: projection.viewer, mode: .open)) }
                        .accessibilityIdentifier(UIIdentifiers.defenderModeButton(.open))
                }
                .buttonStyle(.borderedProminent)
            }
            .accessibilityIdentifier(UIIdentifiers.Panel.defenderMode.rawValue)
        }
    }

    private func dealFinishedBadge(result: DealResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last result")
                .font(.headline)
            Text(UIIdentifiers.encode(result.kind))
                .font(.body.monospaced())
                .accessibilityIdentifier(UIIdentifiers.dealResultKind)
            switch result.kind {
            case let .game(declarer, contract, _):
                Text("Declarer: \(declarer.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(UIIdentifiers.dealResultDeclarer)
                Text("Contract: \(contract.description)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(UIIdentifiers.dealResultContract)
                Text("Tricks: \(result.trickCounts[declarer] ?? 0)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(UIIdentifiers.dealResultTricks)
            case let .misere(declarer):
                Text("Declarer: \(declarer.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(UIIdentifiers.dealResultDeclarer)
                Text("Tricks: \(result.trickCounts[declarer] ?? 0)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(UIIdentifiers.dealResultTricks)
            case let .halfWhist(declarer, contract, _):
                Text("Declarer: \(declarer.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(UIIdentifiers.dealResultDeclarer)
                Text("Contract: \(contract.description)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(UIIdentifiers.dealResultContract)
            case .passedOut, .allPass:
                EmptyView()
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier(UIIdentifiers.Panel.dealFinished.rawValue)
    }

    private func gameOverPanel(summary: MatchSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Game over")
                .font(.title.bold())
                .accessibilityIdentifier(UIIdentifiers.gameOverTitle)
            if let winner = summary.standings.first {
                Text("Winner: \(winner.player.rawValue)")
                    .font(.headline)
                    .accessibilityIdentifier(UIIdentifiers.gameOverWinner)
            }
            Text("Deals played: \(summary.dealsPlayed)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(UIIdentifiers.gameOverDealsPlayed)
            Divider()
            Text("Standings")
                .font(.headline)
            ForEach(Array(summary.standings.enumerated()), id: \.offset) { index, standing in
                HStack(spacing: 14) {
                    Text("\(index + 1).")
                        .frame(width: 28, alignment: .leading)
                    Text(standing.player.rawValue)
                        .frame(minWidth: 72, alignment: .leading)
                        .accessibilityIdentifier(UIIdentifiers.gameOverStandingPlayer(rank: index + 1))
                    Text("\(standing.pool)")
                        .frame(minWidth: 36, alignment: .trailing)
                        .accessibilityIdentifier(UIIdentifiers.gameOverStandingPool(rank: index + 1))
                    Text("\(standing.mountain)")
                        .frame(minWidth: 56, alignment: .trailing)
                        .accessibilityIdentifier(UIIdentifiers.gameOverStandingMountain(rank: index + 1))
                    Text(standing.balance.formatted(.number.precision(.fractionLength(1))))
                        .frame(minWidth: 56, alignment: .trailing)
                        .accessibilityIdentifier(UIIdentifiers.gameOverStandingBalance(rank: index + 1))
                }
                .font(.caption)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier(UIIdentifiers.Panel.gameOver.rawValue)
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
                            CardView(
                                card: .known(play.card),
                                region: .trick(seat: play.player)
                            )
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
        .accessibilityIdentifier(UIIdentifiers.Panel.currentTrick.rawValue)
    }

    private var talonAndDiscard: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading) {
                Text("Talon")
                    .font(.headline)
                CardRowView(cards: projection.talon, region: .talon)
            }
            .accessibilityIdentifier(UIIdentifiers.Panel.talon.rawValue)
            VStack(alignment: .leading) {
                Text("Discard")
                    .font(.headline)
                CardRowView(cards: projection.discard, region: .discard)
            }
            .accessibilityIdentifier(UIIdentifiers.Panel.discardArea.rawValue)
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
        .accessibilityIdentifier(UIIdentifiers.Panel.table.rawValue)
    }

    private var eventPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Log")
                .font(.headline)
            ForEach(Array(eventLog.suffix(12).enumerated()), id: \.offset) { index, event in
                Text(event)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(UIIdentifiers.eventLogEntry(index: index))
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier(UIIdentifiers.Panel.eventLog.rawValue)
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

    private var isTotusDeclaration: Bool {
        if case let .awaitingContract(_, finalBid) = projection.phase {
            return finalBid == .totus
        }
        return false
    }
}
