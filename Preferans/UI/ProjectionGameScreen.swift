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
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
        VStack(spacing: 0) {
            phaseStatusBar
            TableView(projection: projection, animationNamespace: cardNamespace)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ActionBarView(projection: projection, selectedDiscard: selectedDiscard, onSend: onSend)
            viewerHandFan
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 4)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .feltBackground()
    }

    // MARK: - Regular (iPad / wider)

    private var regularBody: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                phaseStatusBar
                TableView(projection: projection, animationNamespace: cardNamespace)
                    .padding(.top, 8)
                    .frame(maxHeight: .infinity)
                ActionBarView(projection: projection, selectedDiscard: selectedDiscard, onSend: onSend)
                viewerHandFan
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            ScoreBoardView(score: projection.score)
                .frame(width: 360)
        }
        .padding(.vertical, 16)
        .padding(.trailing, 16)
        .feltBackground()
    }

    // MARK: - Status bar

    private var phaseStatusBar: some View {
        HStack(spacing: 8) {
            // iOS 26 stops surfacing inline nav-bar titles to UI tests /
            // VoiceOver, so the phase title also lives here as a visible
            // tag carrying its accessibility id.
            Text(projection.phase.title)
                .font(.caption.bold())
                .foregroundStyle(TableTheme.inkCream)
                .lineLimit(1)
                .accessibilityIdentifier(UIIdentifiers.phaseTitle)
            Text(projection.message)
                .font(.caption)
                .foregroundStyle(TableTheme.inkCreamSoft)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(UIIdentifiers.phaseMessage)
            Text("you: \(displayName(for: projection.viewer))")
                .font(.caption2)
                .foregroundStyle(TableTheme.inkCreamDim)
                .accessibilityIdentifier(UIIdentifiers.viewerLabel)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .feltBand()
    }

    // MARK: - Viewer hand

    @ViewBuilder
    private var viewerHandFan: some View {
        if let seat = viewerSeat {
            let isDiscardPhase = projection.legal.canDiscard
            let playable: Set<Card> = isDiscardPhase ? [] : Set(projection.legal.playableCards)
            let selected: Set<Card> = isDiscardPhase ? selectedDiscard : []
            let talonKnown: [Card] = isDiscardPhase ? projection.talon.compactMap(\.knownCard) : []
            // Merge hand + talon and re-sort so the user sees a single
            // suit/rank-ordered fan instead of "hand, then two talon cards
            // appended at the right end."
            let cards: [ProjectedCard] = isDiscardPhase
                ? sortedHandFan(seat.hand + projection.talon)
                : seat.hand
            VStack(spacing: 4) {
                CardFanView(
                    cards: cards,
                    playableCards: playable,
                    selectedCards: selected,
                    talonCards: Set(talonKnown),
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
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(handRail)
        }
    }

    /// A "leather card rest" rail behind the viewer's hand — slightly darker
    /// than the felt, edged with a thin gold line up top so the cards have a
    /// clear shelf to sit on instead of floating against the felt.
    private var handRail: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.32),
                    Color.black.opacity(0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(TableTheme.gold.opacity(0.25))
                .frame(height: 0.5)
        }
    }

    private func sortedHandFan(_ cards: [ProjectedCard]) -> [ProjectedCard] {
        cards.sorted { lhs, rhs in
            switch (lhs.knownCard, rhs.knownCard) {
            case let (l?, r?): return l < r
            case (_, nil):     return true
            case (nil, _):     return false
            }
        }
    }

    private func ownerNamePlate(seat: SeatProjection) -> some View {
        HStack(spacing: 6) {
            if seat.isCurrentActor {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.caption2)
                    .foregroundStyle(TableTheme.goldBright)
            }
            Text(seat.displayName)
                .font(.caption.bold())
                .foregroundStyle(seat.isCurrentActor ? TableTheme.goldBright : TableTheme.inkCream)
                .accessibilityIdentifier(UIIdentifiers.scorePlayer(seat.player))
            if seat.isDealer {
                Text("Dealer")
                    .font(.caption2)
                    .foregroundStyle(TableTheme.inkCreamSoft)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.30), in: Capsule())
                    .accessibilityIdentifier(UIIdentifiers.seatDealer(seat.player))
            }
            if seat.isCurrentActor {
                Text("Your turn")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .foregroundStyle(TableTheme.feltDeep)
                    .background(TableTheme.goldBright, in: Capsule())
                    .accessibilityIdentifier(UIIdentifiers.seatCurrentActor(seat.player))
            }
            Spacer()
            Text("Tricks: \(seat.trickCount)")
                .font(.caption2)
                .foregroundStyle(TableTheme.inkCreamSoft)
                .accessibilityIdentifier(UIIdentifiers.seatTrickCount(seat.player))
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
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
            // Human-readable headline; the encoded id stays in a hidden
            // accessibility carrier so UI tests can still pin on the kind.
            Text(humanResultHeadline(result))
                .font(.title2.bold())
                .accessibilityIdentifier(UIIdentifiers.dealResultKind)
            Text(UIIdentifiers.encode(result.kind))
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            switch result.kind {
            case let .game(declarer, contract, _):
                resultLine("Declarer", displayName(for: declarer), idForValue: UIIdentifiers.dealResultDeclarer)
                resultLine("Contract", contract.description, idForValue: UIIdentifiers.dealResultContract)
                resultLine("Tricks won", "\(result.trickCounts[declarer] ?? 0)", idForValue: UIIdentifiers.dealResultTricks)
            case let .misere(declarer):
                resultLine("Declarer", displayName(for: declarer), idForValue: UIIdentifiers.dealResultDeclarer)
                resultLine("Tricks taken", "\(result.trickCounts[declarer] ?? 0)", idForValue: UIIdentifiers.dealResultTricks)
            case let .halfWhist(declarer, contract, _):
                resultLine("Declarer", displayName(for: declarer), idForValue: UIIdentifiers.dealResultDeclarer)
                resultLine("Contract", contract.description, idForValue: UIIdentifiers.dealResultContract)
            case .passedOut, .allPass:
                Text("Hand passed out")
                    .foregroundStyle(.secondary)
            }
            if projection.legal.canStartDeal {
                Button {
                    onSend(.startDeal(dealer: nil, deck: nil))
                    activeSheet = nil
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start next deal")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
                .accessibilityIdentifier(UIIdentifiers.buttonStartDeal)
            }
            Divider()
            ScoreBoardView(score: projection.score)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.Panel.dealFinished.rawValue)
    }

    private func humanResultHeadline(_ result: DealResult) -> String {
        switch result.kind {
        case let .game(declarer, contract, whisters):
            let made = (result.trickCounts[declarer] ?? 0) >= contract.tricks
            let verb = made ? "made" : "failed"
            let tricks = result.trickCounts[declarer] ?? 0
            let whoString: String
            if whisters.isEmpty {
                whoString = ""
            } else {
                let names = whisters.map { displayName(for: $0) }.joined(separator: " + ")
                whoString = " · whisters: \(names)"
            }
            return "\(displayName(for: declarer)) \(verb) \(contract.description) (\(tricks) tricks)\(whoString)"
        case let .misere(declarer):
            let tricks = result.trickCounts[declarer] ?? 0
            let verb = tricks == 0 ? "made misère" : "failed misère"
            return "\(displayName(for: declarer)) \(verb) (\(tricks) tricks taken)"
        case let .halfWhist(declarer, contract, halfWhister):
            return "\(displayName(for: declarer)) granted \(contract.description) – \(displayName(for: halfWhister)) half-whisted"
        case .passedOut:
            return "All defenders passed – declarer awarded the contract"
        case .allPass:
            return "Hand passed out (raspasy)"
        }
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
