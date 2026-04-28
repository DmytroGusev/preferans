import SwiftUI

struct TableView: View {
    @EnvironmentObject private var game: GameViewModel
    @State private var selectedBidLevel: Int = 6

    var body: some View {
        ZStack {
            tableBackground

            VStack(spacing: 8) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 6)

                centerTable
                    .padding(.horizontal, 14)

                controlsSection
                    .padding(.horizontal, 16)

                Spacer(minLength: 0)

                bottomHand
                    .padding(.horizontal, 10)

                bottomActions
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var tableBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.03, green: 0.14, blue: 0.12),
                Color(red: 0.07, green: 0.28, blue: 0.23),
                Color(red: 0.02, green: 0.1, blue: 0.09)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Circle()
                .fill(Color.white.opacity(0.05))
                .blur(radius: 120)
                .offset(x: -130, y: -220)
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            HStack(alignment: .top, spacing: 12) {
                claimMenu

                VStack(alignment: .leading, spacing: 4) {
                    Text("Preferans")
                        .font(.system(size: 26, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text("Contract")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                Text((game.declaredContract ?? game.currentBid?.contract)?.title ?? "—")
                    .font(.headline.bold())
                    .foregroundStyle(contractAccentColor)
            }
        }
    }

    private var centerTable: some View {
        GeometryReader { geometry in
            ZStack {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.14, green: 0.42, blue: 0.35),
                                Color(red: 0.05, green: 0.2, blue: 0.17),
                                Color(red: 0.02, green: 0.08, blue: 0.07)
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 300
                        )
                    )
                    .overlay(
                        Ellipse()
                            .stroke(Color(red: 0.84, green: 0.72, blue: 0.43).opacity(0.2), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 30, y: 18)

                Ellipse()
                    .inset(by: 18)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)

                if let topPlayer = topPlayer {
                    tableSeat(
                        player: topPlayer,
                        width: 150,
                        position: CGPoint(x: geometry.size.width / 2, y: 58)
                    )
                }

                if let leftPlayer = leftPlayer {
                    tableSeat(
                        player: leftPlayer,
                        width: 140,
                        position: CGPoint(x: 78, y: geometry.size.height / 2 - 4)
                    )
                }

                if let rightPlayer = rightPlayer {
                    tableSeat(
                        player: rightPlayer,
                        width: 140,
                        position: CGPoint(x: geometry.size.width - 78, y: geometry.size.height / 2 - 4)
                    )
                }

                VStack(spacing: 10) {
                    HStack {
                        phasePill
                        Spacer()
                        talonPreview
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                    Spacer()

                    if game.activeTrick.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "suit.spade.fill")
                                .font(.system(size: 34))
                                .foregroundStyle(Color(red: 0.85, green: 0.73, blue: 0.43))
                            Text("Ready for the next trick")
                                .font(.headline)
                                .foregroundStyle(.white.opacity(0.9))
                            Text(phaseDescription)
                                .font(.subheadline)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.64))
                                .frame(maxWidth: 220)
                        }
                    } else {
                        HStack(spacing: 18) {
                            ForEach(game.activeTrick) { play in
                                VStack(spacing: 8) {
                                    PlayingCardView(card: play.card)
                                    Text(playerName(for: play.playerID))
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                            }
                        }
                    }

                    Spacer()

                    if let bid = game.currentBid,
                       let bidder = game.players.first(where: { $0.id == bid.playerID }) {
                        Text(centerFooterText(bidder: bidder, bid: bid))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.82))
                            .padding(.bottom, 20)
                    } else {
                        Spacer()
                            .frame(height: 20)
                    }
                }
            }
        }
        .frame(height: 286)
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let proposal = game.trickClaimProposal {
                claimProposalSection(proposal)
            }

            if game.phase == .bidding, let current = game.currentPlayer {
                Text("Current bidder: \(current.name)")
                    .font(.headline)
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 10) {
                    biddingStatusStrip

                    compactSpecialBids(for: current)
                    compactBidSuitPicker(for: current)

                    Text("Choose level first, then suit or NT. Your cards stay visible below while bidding.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                }
            }

            if game.isTrickAwaitingCollection {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Review the trick")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Cards stay on the table until you collect them, so you can see who played what.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.68))
                    Button("Collect Trick") {
                        game.collectCompletedTrick()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.78, green: 0.62, blue: 0.28))
                }
                .padding(12)
                .background(Color.black.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if game.phase == .takingTalon {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Take the talon")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Declarer takes both cards from the talon before discarding two cards.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.68))
                    Button("Take Talon") {
                        game.takeTalon()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.78, green: 0.62, blue: 0.28))
                }
            }

            if game.phase == .discarding {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Discard Two Cards")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Select exactly 2 cards from the declarer's 12-card hand. The discard stays hidden.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.68))
                    Text("Selected: \(game.selectedDiscardIDs.count)/2")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(red: 0.87, green: 0.75, blue: 0.43))
                    Button("Confirm Discard") {
                        game.confirmDiscard()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!game.canConfirmDiscard)
                    .tint(Color(red: 0.78, green: 0.62, blue: 0.28))
                }
            }

            if game.phase == .declaringContract {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Order Final Contract")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("The final game cannot be lower than the winning auction bid.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.68))

                    ForEach(groupedFinalContracts, id: \.0) { tricks, contracts in
                        HStack(spacing: 10) {
                            Text("\(tricks)")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(Color(red: 0.89, green: 0.78, blue: 0.49))
                                .frame(width: 24, alignment: .leading)

                            ForEach(contracts, id: \.title) { contract in
                                Button(contractButtonTitle(contract)) {
                                    game.declareFinalContract(contract)
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 62, height: 44)
                                .background(Color.black.opacity(0.22))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(contractStrokeColor(contract).opacity(0.6), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                }
            }

            if game.phase == .whisting, let current = game.currentPlayer {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Whisting: \(current.name)")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Defenders decide whether to oppose the declarer.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.68))
                    HStack(spacing: 10) {
                        ForEach(whistOptions(for: current), id: \.rawValue) { option in
                            Button(option.title) {
                                game.chooseWhist(option, for: current)
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.22))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
            }

            if game.phase == .handFinished {
                VStack(alignment: .leading, spacing: 10) {
                    Text(game.handSummary ?? game.auctionSummary ?? "Hand finished.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                    if let summary = game.partySummary {
                        Text(summary)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(red: 0.88, green: 0.76, blue: 0.47))
                        ForEach(game.partyBreakdown, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.72))
                        }
                    }
                    Button(game.partySummary == nil ? "Next Hand" : "Back To Lobby") {
                        if game.partySummary == nil {
                            game.startNextHand()
                        } else {
                            game.resetToLobby()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.78, green: 0.62, blue: 0.28))
                }
            }

            if showOpenHandsSection {
                revealedHandsSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomHand: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(handSectionTitle)
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                if let handPlayer {
                    Text(handCounterText(for: handPlayer))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Group {
                PreviewHandView(
                    cards: handPlayer?.hand ?? [],
                    playableCards: Set((handPlayer?.hand ?? []).filter { card in
                        handPlayer.map { isHandActionEnabled(card, for: $0) } ?? false
                    }),
                    selectedCardIDs: game.selectedDiscardIDs,
                    onTap: { card in
                        if let handPlayer {
                            handleTap(on: card, for: handPlayer)
                        }
                    }
                )
            }
            .frame(height: 172)
            .padding(.top, 2)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.16), Color.clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
        }
    }

    private var bottomActions: some View {
        HStack {
            Button("Back To Lobby") {
                game.resetToLobby()
            }
            .buttonStyle(.bordered)

            Spacer()
        }
    }

    private var statusText: String {
        let contractText = (game.declaredContract ?? game.currentBid?.contract)?.title ?? "No contract yet"
        return "\(game.phase.title) • \(contractText)"
    }

    private var phaseDescription: String {
        switch game.phase {
        case .setup:
            return "Configure players and start the hand."
        case .bidding:
            return "Bid for trump and decide who will declare."
        case .takingTalon:
            return "Declarer takes the talon before discarding."
        case .discarding:
            return "Declarer discards any two cards face down."
        case .declaringContract:
            return "Declarer orders the final game after seeing the talon."
        case .whisting:
            return "Defenders choose whist, pass or half-whist."
        case .playing:
            return "Follow suit first. If you cannot, trump when possible."
        case .handFinished:
            return "This hand is over. Review scores or return to the lobby."
        }
    }

    private var phasePill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(red: 0.83, green: 0.68, blue: 0.35))
                .frame(width: 8, height: 8)
            Text(game.phase.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.22))
        .clipShape(Capsule())
    }

    private var talonPreview: some View {
        HStack(spacing: -24) {
            ForEach(Array(game.talon.prefix(2).enumerated()), id: \.offset) { _, card in
                PlayingCardView(
                    card: card,
                    faceUp: game.phase != .bidding,
                    isPlayable: true,
                    isCompact: true
                )
            }
        }
        .padding(.trailing, 10)
    }

    private var visiblePlayers: [Player] {
        Array(game.players.prefix(game.playerCount))
    }

    private var opponentPlayers: [Player] {
        visiblePlayers.filter { $0.seat != game.localSeat && !$0.isSittingOut }
    }

    private var topPlayer: Player? {
        opponentPlayers.first
    }

    private var sidePlayers: [Player] {
        Array(opponentPlayers.dropFirst())
    }

    private var leftPlayer: Player? {
        sidePlayers.first
    }

    private var rightPlayer: Player? {
        sidePlayers.count > 1 ? sidePlayers[1] : nil
    }

    private var localPlayer: Player? {
        visiblePlayers.first(where: { $0.seat == game.localSeat })
    }

    private var handPlayer: Player? {
        switch game.phase {
        case .discarding, .declaringContract, .takingTalon:
            return game.declarer
        case .playing:
            return game.currentPlayer
        default:
            return localPlayer
        }
    }

    private var showOpenHandsSection: Bool {
        game.phase == .playing && !revealedPlayers.isEmpty
    }

    private var revealedPlayers: [Player] {
        game.activePlayers.filter { game.openHandPlayerIDs.contains($0.id) }
    }

    private func playerName(for id: UUID) -> String {
        game.players.first(where: { $0.id == id })?.name ?? "Player"
    }

    private func isPlayable(_ card: Card, for player: Player) -> Bool {
        guard game.phase == .playing else { return false }
        guard !game.isTrickAwaitingCollection else { return false }
        guard player.seat == game.currentTurnSeat else { return false }

        guard let leadSuit = game.activeTrick.first?.card.suit else { return true }
        if player.hand.contains(where: { $0.suit == leadSuit }) {
            return card.suit == leadSuit
        }
        if let trump = game.currentTrump, player.hand.contains(where: { $0.suit == trump }) {
            return card.suit == trump
        }
        return true
    }

    private func isHandActionEnabled(_ card: Card, for player: Player) -> Bool {
        switch game.phase {
        case .discarding:
            return player.id == game.declarerID
        case .playing:
            return isPlayable(card, for: player)
        default:
            return false
        }
    }

    private func handleTap(on card: Card, for player: Player) {
        switch game.phase {
        case .discarding:
            game.toggleDiscardSelection(card)
        case .playing:
            game.playCard(card, from: player)
        default:
            break
        }
    }

    private func tableSeat(player: Player, width: CGFloat, position: CGPoint) -> some View {
        VStack(spacing: 6) {
            CardBackStackView(count: player.hand.count, scale: 0.42)

            SeatBadgeView(
                player: player,
                isActive: player.seat == game.currentTurnSeat && !game.isTrickAwaitingCollection,
                isDeclarer: player.id == game.declarerID,
                isPassed: game.passedBidderIDs.contains(player.id) && game.phase == .bidding,
                compact: true
            )
        }
        .frame(width: width)
        .position(position)
    }

    private var biddingStatusStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let summary = game.auctionSummary {
                Text(summary)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.84))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(game.activePlayers) { player in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor(for: player))
                                .frame(width: 8, height: 8)
                            Text(statusText(for: player))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.92))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.22))
                        .clipShape(Capsule())
                    }
                }
            }
        }
    }

    private func statusText(for player: Player) -> String {
        if player.id == game.currentBid?.playerID, let contract = game.currentBid?.contract {
            return "\(player.name) • \(contract.title)"
        }
        if game.passedBidderIDs.contains(player.id) {
            return "\(player.name) • pass"
        }
        if player.seat == game.currentTurnSeat {
            return "\(player.name) • turn"
        }
        return "\(player.name) • waiting"
    }

    private func statusColor(for player: Player) -> Color {
        if player.id == game.currentBid?.playerID {
            return contractAccentColor
        }
        if game.passedBidderIDs.contains(player.id) {
            return .white.opacity(0.36)
        }
        if player.seat == game.currentTurnSeat {
            return Color(red: 0.87, green: 0.74, blue: 0.42)
        }
        return .white.opacity(0.18)
    }

    private var contractAccentColor: Color {
        if let trump = game.currentTrump {
            return trump.color
        }
        if case .misere = game.declaredContract ?? game.currentBid?.contract {
            return Color(red: 0.83, green: 0.58, blue: 0.58)
        }
        if case .noTrump = game.declaredContract ?? game.currentBid?.contract {
            return Color(red: 0.87, green: 0.75, blue: 0.43)
        }
        return .white
    }

    private func compactBidSuitPicker(for current: Player) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Suit.allCases) { suit in
                    let contract = Contract.suited(tricks: selectedBidLevel, trump: suit)
                    Button {
                        game.placeBid(contract, for: current)
                    } label: {
                        Text(suit.symbol)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(suit.color == Color(red: 0.08, green: 0.08, blue: 0.1) ? .white : suit.color)
                            .frame(width: 40, height: 34)
                            .background(Color.black.opacity(0.22))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(suit.color.opacity(game.canBid(contract) ? 0.72 : 0.18), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .opacity(game.canBid(contract) ? 1 : 0.38)
                    }
                    .disabled(!game.canBid(contract))
                }

                let noTrump = Contract.noTrump(tricks: selectedBidLevel)
                Button {
                    game.placeBid(noTrump, for: current)
                } label: {
                    Text("NT")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 34)
                        .background(Color.black.opacity(0.22))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color(red: 0.86, green: 0.74, blue: 0.43).opacity(game.canBid(noTrump) ? 0.72 : 0.18), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .opacity(game.canBid(noTrump) ? 1 : 0.38)
                }
                .disabled(!game.canBid(noTrump))

                compactBidLevelControl
            }
        }
    }

    private func compactSpecialBids(for current: Player) -> some View {
        HStack(spacing: 8) {
            let misere = Contract.misere
            Button {
                game.placeBid(misere, for: current)
            } label: {
                HStack(spacing: 6) {
                    Text("Misere")
                        .font(.subheadline.weight(.semibold))
                    Text("0")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(red: 0.36, green: 0.11, blue: 0.11).opacity(0.58))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(red: 0.84, green: 0.58, blue: 0.58).opacity(game.canBid(misere) ? 0.55 : 0.18), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(game.canBid(misere) ? 1 : 0.38)
            }
            .disabled(!game.canBid(misere))

            Button("Pass") {
                game.passBid(for: current)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Spacer(minLength: 0)
        }
    }

    private var compactBidLevelControl: some View {
        HStack(spacing: 4) {
            Button {
                selectedBidLevel = max(6, selectedBidLevel - 1)
            } label: {
                Image(systemName: "minus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
            }

            Text("\(selectedBidLevel)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color(red: 0.89, green: 0.78, blue: 0.49))
                .frame(width: 24)

            Button {
                selectedBidLevel = min(10, selectedBidLevel + 1)
            } label: {
                Image(systemName: "plus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 34)
        .background(Color.black.opacity(0.22))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var claimMenu: some View {
        Menu {
            if let current = game.currentPlayer, game.canCurrentPlayerProposeClaim {
                ForEach(game.availableClaimTotals(for: current), id: \.self) { total in
                    Button("Propose \(current.name) takes \(total)") {
                        game.proposeClaim(totalTricks: total)
                    }
                }
            } else {
                Text("Claim available only during play")
            }
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.black.opacity(0.22))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func claimProposalSection(_ proposal: TrickClaimProposal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fast Settlement Proposal")
                .font(.headline)
                .foregroundStyle(.white)

            Text(claimProposalText(proposal))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(game.activePlayers) { player in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(claimResponseColor(for: player, proposal: proposal))
                                .frame(width: 8, height: 8)
                            Text(claimResponseText(for: player, proposal: proposal))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.92))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.22))
                        .clipShape(Capsule())
                    }
                }
            }

            if let current = game.currentPlayer, current.id != proposal.proposerID {
                HStack(spacing: 10) {
                    Button("Accept") {
                        game.respondToClaim(accept: true, by: current)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.24, green: 0.52, blue: 0.32))

                    Button("Reject") {
                        game.respondToClaim(accept: false, by: current)
                    }
                    .buttonStyle(.bordered)

                    Menu("Counter") {
                        if let targetPlayer = game.players.first(where: { $0.id == proposal.targetPlayerID }) {
                            ForEach(game.availableClaimTotals(for: targetPlayer), id: \.self) { total in
                                Button("\(total) tricks") {
                                    game.counterClaim(with: total, by: current)
                                }
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let current = game.currentPlayer, current.id == proposal.proposerID {
                Button("Withdraw Proposal") {
                    game.cancelClaimProposal()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.16))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func centerFooterText(bidder: Player, bid: Bid) -> String {
        if let declared = game.declaredContract {
            return "Declarer: \(bidder.name) • ordered \(declared.title)"
        }
        return "Best bid: \(bidder.name) • \(bid.contract.title)"
    }

    private var groupedFinalContracts: [(Int, [Contract])] {
        let groups = Dictionary(grouping: game.availableFinalContracts) { contract -> Int in
            switch contract {
            case let .suited(tricks, _), let .noTrump(tricks):
                return tricks
            case .misere:
                return 0
            case .raspasy:
                return -1
            }
        }
        return groups.keys.sorted().map { ($0, groups[$0] ?? []) }
    }

    private func contractButtonTitle(_ contract: Contract) -> String {
        switch contract {
        case let .suited(_, trump):
            return trump.symbol
        case .noTrump:
            return "NT"
        case .misere:
            return "Mis"
        case .raspasy:
            return "R"
        }
    }

    private func contractStrokeColor(_ contract: Contract) -> Color {
        switch contract {
        case let .suited(_, trump):
            return trump.color
        case .noTrump:
            return Color(red: 0.87, green: 0.75, blue: 0.43)
        case .misere:
            return Color(red: 0.83, green: 0.58, blue: 0.58)
        case .raspasy:
            return .white
        }
    }

    private func whistOptions(for player: Player) -> [WhistDecision] {
        guard game.phase == .whisting else { return [] }
        guard let contract = game.declaredContract, contract.isTrickGame else { return [] }
        let orderedDefenders = game.defenders.sorted { $0.seat < $1.seat }
        guard orderedDefenders.contains(where: { $0.id == player.id }) else { return [] }

        if orderedDefenders.first?.id == player.id {
            return [.pass, .whist]
        }

        if orderedDefenders.last?.id == player.id,
           let first = orderedDefenders.first,
           game.whistDecisions[first.id] == .pass,
           let target = contract.targetTricks,
           target <= 7 {
            return [.pass, .halfWhist, .whist]
        }

        return [.pass, .whist]
    }

    private func handCounterText(for player: Player) -> String {
        switch game.phase {
        case .discarding:
            return "\(player.hand.count) cards • select 2 discard"
        case .playing:
            if game.openHandPlayerIDs.contains(player.id), let controller = game.lightWhistController {
                return "\(player.hand.count) cards • controlled by \(controller.name)"
            }
            return "\(player.hand.count) cards"
        default:
            return "\(player.hand.count) cards"
        }
    }

    private var handSectionTitle: String {
        switch game.phase {
        case .discarding, .declaringContract, .takingTalon:
            return "\(handPlayer?.name ?? "Declarer") hand"
        case .playing:
            return "\(handPlayer?.name ?? "Current") hand"
        default:
            return "Your hand"
        }
    }

    private var revealedHandsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let controller = game.lightWhistController,
               game.openHandPlayerIDs.count > 1 {
                Text("Light Whist: \(controller.name) controls both defending hands")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.88, green: 0.76, blue: 0.47))
            } else {
                Text("Open Hands")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.88, green: 0.76, blue: 0.47))
            }

            ForEach(revealedPlayers) { player in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(player.name) hand")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(player.hand) { card in
                                PlayingCardView(
                                    card: card,
                                    faceUp: true,
                                    isPlayable: player.seat == game.currentTurnSeat && isHandActionEnabled(card, for: player),
                                    isCompact: true
                                )
                                .onTapGesture {
                                    handleTap(on: card, for: player)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func claimProposalText(_ proposal: TrickClaimProposal) -> String {
        let proposer = playerName(for: proposal.proposerID)
        let target = playerName(for: proposal.targetPlayerID)
        return "\(proposer) proposes to stop the hand and record \(target) for \(proposal.claimedTotalTricks) tricks."
    }

    private func claimResponseText(for player: Player, proposal: TrickClaimProposal) -> String {
        if player.id == proposal.proposerID {
            return "\(player.name) • proposed"
        }
        return "\(player.name) • \(proposal.response(for: player.id).title)"
    }

    private func claimResponseColor(for player: Player, proposal: TrickClaimProposal) -> Color {
        if player.id == proposal.proposerID {
            return Color(red: 0.87, green: 0.74, blue: 0.42)
        }
        switch proposal.response(for: player.id) {
        case .pending:
            return .white.opacity(0.3)
        case .accepted:
            return Color(red: 0.24, green: 0.52, blue: 0.32)
        case .rejected:
            return Color(red: 0.66, green: 0.22, blue: 0.2)
        }
    }
}
