import SwiftUI
import PreferansEngine

public struct ProjectionGameScreen: View {
    public var projection: PlayerGameProjection
    public var eventLog: [String]
    public var onSend: (PreferansAction) -> Void

    private enum Sheet: String, Identifiable {
        case score, log, result
        var id: String { rawValue }
    }

    @State private var selectedDiscard: Set<Card> = []
    @State private var activeSheet: Sheet?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Namespace private var cardNamespace

    public init(projection: PlayerGameProjection, eventLog: [String] = [], onSend: @escaping (PreferansAction) -> Void) {
        self.projection = projection
        self.eventLog = eventLog
        self.onSend = onSend
    }

    public var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                compactBody
            } else {
                regularBody
            }
        }
        .navigationTitle(projection.phase.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .score:  scoreSheet
            case .log:    logSheet
            case .result: resultSheet
            }
        }
        .onChange(of: projection.sequence) { _, _ in
            if hasResultToShow { activeSheet = .result }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button { activeSheet = .score } label: {
                Image(systemName: "list.number")
                    .accessibilityLabel("Scoresheet")
            }
        }
        ToolbarItem(placement: .automatic) {
            Menu {
                Button("Event log") { activeSheet = .log }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("Developer menu")
            }
        }
    }

    // MARK: - Compact (iPhone)

    private var compactBody: some View {
        VStack(spacing: 8) {
            phaseStatusBar
            TableView(projection: projection, animationNamespace: cardNamespace)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ActionBarView(projection: projection, selectedDiscard: selectedDiscard, onSend: onSend)
            viewerHandFan
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Regular (iPad / wider)

    private var regularBody: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 12) {
                phaseStatusBar
                TableView(projection: projection, animationNamespace: cardNamespace)
                    .frame(maxHeight: .infinity)
                ActionBarView(projection: projection, selectedDiscard: selectedDiscard, onSend: onSend)
                viewerHandFan
                    .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity)
            ScoreBoardView(score: projection.score)
                .frame(width: 360)
        }
        .padding(16)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Status bar

    private var phaseStatusBar: some View {
        HStack(spacing: 8) {
            // Invisible carrier so MatchUIRobot can read the phase title by
            // accessibility id; the visible label is in the navigation bar.
            Text(projection.phase.title)
                .accessibilityIdentifier(UIIdentifiers.phaseTitle)
                .frame(width: 0, height: 0)
                .hidden()
                .accessibilityHidden(false)
            Text(projection.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(UIIdentifiers.phaseMessage)
            Text("you: \(displayName(for: projection.viewer))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityIdentifier(UIIdentifiers.viewerLabel)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial)
    }

    // MARK: - Viewer hand

    @ViewBuilder
    private var viewerHandFan: some View {
        if let seat = viewerSeat {
            let isDiscardPhase = projection.legal.canDiscard
            let playable: Set<Card> = isDiscardPhase ? [] : Set(projection.legal.playableCards)
            let selected: Set<Card> = isDiscardPhase ? selectedDiscard : []
            let cards: [ProjectedCard] = isDiscardPhase ? seat.hand + projection.talon : seat.hand
            VStack(spacing: 0) {
                CardFanView(
                    cards: cards,
                    playableCards: playable,
                    selectedCards: selected,
                    seat: seat.player,
                    size: horizontalSizeClass == .compact ? .standard : .large,
                    animationNamespace: cardNamespace,
                    onTap: { card in
                        if isDiscardPhase {
                            toggleDiscardSelection(card)
                        } else if playable.contains(card) {
                            onSend(.playCard(player: projection.viewer, card: card))
                        }
                    }
                )
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(UIIdentifiers.seatContainer(seat.player))
                ownerNamePlate(seat: seat)
            }
        }
    }

    private func ownerNamePlate(seat: SeatProjection) -> some View {
        HStack(spacing: 6) {
            if seat.isCurrentActor {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            }
            Text(seat.displayName)
                .font(.caption.bold())
                .accessibilityIdentifier(UIIdentifiers.scorePlayer(seat.player))
            if seat.isDealer {
                Text("Dealer")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.thinMaterial, in: Capsule())
                    .accessibilityIdentifier(UIIdentifiers.seatDealer(seat.player))
            }
            if seat.isCurrentActor {
                Text("Your turn")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: Capsule())
                    .accessibilityIdentifier(UIIdentifiers.seatCurrentActor(seat.player))
            }
            Spacer()
            Text("Tricks: \(seat.trickCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(UIIdentifiers.seatTrickCount(seat.player))
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
    }

    // MARK: - Sheets

    private var scoreSheet: some View {
        NavigationStack {
            ScrollView {
                ScoreBoardView(score: projection.score)
                    .padding()
            }
            .navigationTitle("Scoresheet")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") { activeSheet = nil }
                }
            }
        }
    }

    private var logSheet: some View {
        let recent = Array(eventLog.suffix(40))
        return NavigationStack {
            List {
                Section("Recent events") {
                    ForEach(recent.indices.reversed(), id: \.self) { index in
                        Text(recent[index])
                            .font(.caption.monospaced())
                            .accessibilityIdentifier(UIIdentifiers.eventLogEntry(index: index))
                    }
                }
            }
            .navigationTitle("Event log")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") { activeSheet = nil }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(UIIdentifiers.Panel.eventLog.rawValue)
        }
    }

    @ViewBuilder
    private var resultSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if case let .gameOver(summary) = projection.phase {
                        gameOverContent(summary: summary)
                    } else if case let .dealFinished(result) = projection.phase {
                        dealFinishedContent(result: result)
                    }
                }
                .padding()
            }
            .navigationTitle(navigationTitleForResult)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Done") { activeSheet = nil }
                }
            }
        }
    }

    private var navigationTitleForResult: String {
        if case .gameOver = projection.phase { return "Game over" }
        return "Deal complete"
    }

    private func dealFinishedContent(result: DealResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(UIIdentifiers.encode(result.kind))
                .font(.title2.bold().monospaced())
                .accessibilityIdentifier(UIIdentifiers.dealResultKind)
            switch result.kind {
            case let .game(declarer, contract, _):
                resultLine("Declarer", declarer.rawValue, idForValue: UIIdentifiers.dealResultDeclarer)
                resultLine("Contract", contract.description, idForValue: UIIdentifiers.dealResultContract)
                resultLine("Tricks won", "\(result.trickCounts[declarer] ?? 0)", idForValue: UIIdentifiers.dealResultTricks)
            case let .misere(declarer):
                resultLine("Declarer", declarer.rawValue, idForValue: UIIdentifiers.dealResultDeclarer)
                resultLine("Tricks taken", "\(result.trickCounts[declarer] ?? 0)", idForValue: UIIdentifiers.dealResultTricks)
            case let .halfWhist(declarer, contract, _):
                resultLine("Declarer", declarer.rawValue, idForValue: UIIdentifiers.dealResultDeclarer)
                resultLine("Contract", contract.description, idForValue: UIIdentifiers.dealResultContract)
            case .passedOut, .allPass:
                Text("Hand passed out")
                    .foregroundStyle(.secondary)
            }
            Divider()
            ScoreBoardView(score: projection.score)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.Panel.dealFinished.rawValue)
    }

    private func gameOverContent(summary: MatchSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Game over")
                .font(.title.bold())
                .accessibilityIdentifier(UIIdentifiers.gameOverTitle)
            if let winner = summary.standings.first {
                Text("Winner: \(winner.player.rawValue)")
                    .font(.title3.bold())
                    .accessibilityIdentifier(UIIdentifiers.gameOverWinner)
            }
            Text("Deals played: \(summary.dealsPlayed)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(UIIdentifiers.gameOverDealsPlayed)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Standings")
                    .font(.headline)
                ForEach(Array(summary.standings.enumerated()), id: \.offset) { index, standing in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.body.bold())
                            .frame(width: 24, alignment: .leading)
                        Text(standing.player.rawValue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier(UIIdentifiers.gameOverStandingPlayer(rank: index + 1))
                        Text("\(standing.pool)")
                            .font(.body.monospacedDigit())
                            .frame(width: 50, alignment: .trailing)
                            .accessibilityIdentifier(UIIdentifiers.gameOverStandingPool(rank: index + 1))
                        Text("\(standing.mountain)")
                            .font(.body.monospacedDigit())
                            .frame(width: 70, alignment: .trailing)
                            .accessibilityIdentifier(UIIdentifiers.gameOverStandingMountain(rank: index + 1))
                        Text(standing.balance.formatted(.number.precision(.fractionLength(1))))
                            .font(.body.monospacedDigit().weight(.semibold))
                            .frame(width: 60, alignment: .trailing)
                            .accessibilityIdentifier(UIIdentifiers.gameOverStandingBalance(rank: index + 1))
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.Panel.gameOver.rawValue)
    }

    private func resultLine(_ label: String, _ value: String, idForValue: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .accessibilityIdentifier(idForValue)
        }
    }

    // MARK: - Helpers

    private var hasResultToShow: Bool {
        switch projection.phase {
        case .dealFinished, .gameOver: return true
        default:                       return false
        }
    }

    private var viewerSeat: SeatProjection? {
        projection.seats.first { $0.player == projection.viewer }
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
