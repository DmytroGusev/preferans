import AuthenticationServices
import SwiftUI

@MainActor
final class GameViewModel: ObservableObject {
    private enum StorageKey {
        static let onlineProfile = "preferans.onlineProfile"
    }

    @Published var screen: GameScreen = .lobby
    @Published var playerCount: Int = 3
    @Published var ruleSet: PreferansRuleSet = .sochi
    @Published var players: [Player] = [
        Player(name: "You", seat: 0),
        Player(name: "Mila", seat: 1),
        Player(name: "Leo", seat: 2),
        Player(name: "Nika", seat: 3, isSittingOut: true)
    ]
    @Published var dealerSeat: Int = 0
    @Published var phase: Phase = .setup
    @Published var talon: [Card] = []
    @Published var hiddenDiscard: [Card] = []
    @Published var selectedDiscardIDs: Set<String> = []
    @Published var bids: [Bid] = []
    @Published var currentBid: Bid?
    @Published var declaredContract: Contract?
    @Published var declarerID: UUID?
    @Published var passedBidderIDs: Set<UUID> = []
    @Published var auctionSummary: String?
    @Published var whistDecisions: [UUID: WhistDecision] = [:]
    @Published var lightWhistControllerID: UUID?
    @Published var openHandPlayerIDs: Set<UUID> = []
    @Published var activeTrick: [TrickPlay] = []
    @Published var trickHistory: [[TrickPlay]] = []
    @Published var currentTurnSeat: Int = 0
    @Published var invite: RoomInvite?
    @Published var onlineProfile: OnlineProfile?
    @Published var activeRoom: OnlineRoom?
    @Published var joinLinkInput: String = ""
    @Published var pendingInviteCode: String?
    @Published var onlineStatusMessage: String?
    @Published var multiplayerSyncStatus: String?
    @Published var handSummary: String?
    @Published var partySummary: String?
    @Published var partyBreakdown: [String] = []
    @Published var trickClaimProposal: TrickClaimProposal?
    @Published var whistLedger: [UUID: [UUID: Int]] = [:]

    private let roomService: MultiplayerServicing
    private var botTask: Task<Void, Never>?
    private var roomSyncTask: Task<Void, Never>?
    private var snapshotPushTask: Task<Void, Never>?
    private var lastAppliedSnapshotRevision: Int = 0
    private var isApplyingRemoteSnapshot = false

    init(roomService: MultiplayerServicing = CloudKitMultiplayerService.shared) {
        self.roomService = roomService
        restoreOnlineProfile()
        configurePlayers()
        resetWhistLedger()
    }

    var activePlayers: [Player] {
        players
            .filter { !$0.isSittingOut }
            .sorted { $0.seat < $1.seat }
    }

    var auctionPlayers: [Player] {
        activePlayers.filter { !passedBidderIDs.contains($0.id) }
    }

    var currentTrump: Suit? {
        (declaredContract ?? currentBid?.contract)?.trump
    }

    var targetTricks: Int? {
        (declaredContract ?? currentBid?.contract)?.targetTricks
    }

    var currentPlayer: Player? {
        players.first(where: { $0.seat == currentTurnSeat })
    }

    var isTrickAwaitingCollection: Bool {
        phase == .playing && activeTrick.count == activePlayers.count && !activeTrick.isEmpty
    }

    var declarer: Player? {
        players.first(where: { $0.id == declarerID })
    }

    var defenders: [Player] {
        activePlayers.filter { $0.id != declarerID }
    }

    var lightWhistController: Player? {
        players.first(where: { $0.id == lightWhistControllerID })
    }

    var localPlayer: Player? {
        players.first(where: { $0.seat == localSeat })
    }

    var localSeat: Int {
        guard let onlineProfile,
              let participant = activeRoom?.participants.first(where: { $0.playerID == onlineProfile.id }) else {
            return 0
        }
        return participant.seat
    }

    var isSignedIn: Bool {
        onlineProfile != nil
    }

    var canCreateOnlineRoom: Bool {
        onlineProfile != nil && activeRoom == nil
    }

    var canJoinOnlineRoom: Bool {
        onlineProfile != nil && activeRoom == nil
    }

    var isHostOfActiveRoom: Bool {
        guard let onlineProfile, let activeRoom else { return false }
        return activeRoom.hostPlayerID == onlineProfile.id
    }

    var canStartHand: Bool {
        activeRoom == nil || isHostOfActiveRoom
    }

    var availableContracts: [Contract] {
        let currentStrength = currentBid?.strength ?? -1
        return Contract.orderedContracts.filter { contract in
            guard contract != .raspasy else { return false }
            if case .misere = contract {
                return canCurrentPlayerBidMisere && contract.strength > currentStrength
            }
            return contract.strength > currentStrength
        }
    }

    var availableFinalContracts: [Contract] {
        guard let winning = currentBid?.contract else { return [] }
        if winning == .misere {
            return [.misere]
        }
        return Contract.orderedContracts.filter { contract in
            guard contract != .misere else { return false }
            guard contract != .raspasy else { return false }
            return contract.strength >= winning.strength
        }
    }

    var canCurrentPlayerBidMisere: Bool {
        guard let currentPlayer else { return false }
        return canBid(.misere, by: currentPlayer)
    }

    var isLocalTurn: Bool {
        guard let currentPlayer else { return false }
        return canLocalUserControl(currentPlayer)
    }

    var canConfirmDiscard: Bool {
        selectedDiscardIDs.count == 2
    }

    var hasFinishedParty: Bool {
        activePlayers.allSatisfy { $0.pool >= ruleSet.targetPool }
    }

    var canCurrentPlayerProposeClaim: Bool {
        phase == .playing && currentPlayer != nil
    }

    func configurePlayers() {
        syncDisplayNames()
        for index in players.indices {
            if index >= playerCount {
                players[index].isSittingOut = true
            } else if playerCount == 4 {
                players[index].isSittingOut = index == dealerSeat
            } else {
                players[index].isSittingOut = false
            }
        }
        resetWhistLedger()
        recalculateDisplayScores()
    }

    func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                onlineStatusMessage = "Apple sign-in did not return a usable account."
                return
            }

            let existing = onlineProfile?.displayName ?? players[localSeat].name
            let name = PersonNameComponentsFormatter().string(from: credential.fullName ?? PersonNameComponents())
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = name.isEmpty ? existing : name

            onlineProfile = OnlineProfile(
                id: credential.user,
                displayName: displayName.isEmpty ? "Player" : displayName,
                provider: .apple,
                email: credential.email
            )
            persistOnlineProfile()
            syncDisplayNames()
            onlineStatusMessage = "Signed in as \(onlineProfile?.displayName ?? "Player")."

            if let pendingInviteCode {
                joinRoom(using: pendingInviteCode)
            }
        case let .failure(error):
            onlineStatusMessage = error.localizedDescription
        }
    }

    func signInWithGoogleEmail(email: String, displayName: String) {
        let normalizedEmail = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalizedEmail.contains("@") else {
            onlineStatusMessage = "Enter a valid Gmail or Google email."
            return
        }

        let cleanedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = normalizedEmail
            .split(separator: "@")
            .first
            .map(String.init) ?? "Player"

        onlineProfile = OnlineProfile(
            id: "google:\(normalizedEmail)",
            displayName: cleanedName.isEmpty ? fallbackName : cleanedName,
            provider: .google,
            email: normalizedEmail
        )
        persistOnlineProfile()
        syncDisplayNames()
        onlineStatusMessage = "Signed in with Gmail as \(onlineProfile?.displayName ?? "Player")."

        if let pendingInviteCode {
            joinRoom(using: pendingInviteCode)
        }
    }

    func signInAsGuest(displayName: String) {
        let cleanedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingID = onlineProfile?.provider == .guest ? onlineProfile?.id : nil
        onlineProfile = OnlineProfile(
            id: existingID ?? "guest:\(UUID().uuidString)",
            displayName: cleanedName.isEmpty ? players[localSeat].name : cleanedName,
            provider: .guest
        )
        persistOnlineProfile()
        syncDisplayNames()
        onlineStatusMessage = "Signed in as test guest \(onlineProfile?.displayName ?? "Player")."

        if let pendingInviteCode {
            joinRoom(using: pendingInviteCode)
        }
    }

    func signOutOnlineProfile() {
        stopRoomSync()
        onlineProfile = nil
        activeRoom = nil
        invite = nil
        pendingInviteCode = nil
        joinLinkInput = ""
        lastAppliedSnapshotRevision = 0
        onlineStatusMessage = "Signed out."
        UserDefaults.standard.removeObject(forKey: StorageKey.onlineProfile)
        syncDisplayNames()
        configurePlayers()
    }

    func createInvite() {
        guard let onlineProfile else {
            onlineStatusMessage = "Sign in before creating an online room."
            return
        }

        Task {
            do {
                let room = try await roomService.createRoom(
                    host: onlineProfile,
                    playerCount: playerCount,
                    ruleSet: ruleSet
                )
                let invite = roomService.roomInvite(for: room)
                await MainActor.run {
                    applyRoom(room, invite: invite)
                    onlineStatusMessage = "Room \(room.code) is ready to share."
                }
            } catch {
                await MainActor.run {
                    onlineStatusMessage = error.localizedDescription
                }
            }
        }
    }

    func joinRoomFromInput() {
        guard let code = InviteLinkParser.roomCode(from: joinLinkInput) else {
            onlineStatusMessage = "Enter a valid room code or invite URL."
            return
        }
        joinRoom(using: code)
    }

    func handleIncomingURL(_ url: URL) {
        guard let code = InviteLinkParser.roomCode(from: url) else {
            onlineStatusMessage = "Invite link is not valid."
            return
        }

        pendingInviteCode = code
        joinLinkInput = url.absoluteString

        guard onlineProfile != nil else {
            onlineStatusMessage = "Invite loaded. Sign in to join room \(code)."
            return
        }

        joinRoom(using: code)
    }

    func leaveActiveRoom() {
        guard let activeRoom, let onlineProfile else { return }

        Task {
            _ = await roomService.leaveRoom(roomID: activeRoom.id, playerID: onlineProfile.id)
            await MainActor.run {
                self.activeRoom = nil
                invite = nil
                onlineStatusMessage = "Left the room."
                pendingInviteCode = nil
                joinLinkInput = ""
                lastAppliedSnapshotRevision = 0
                syncDisplayNames()
                configurePlayers()
                stopRoomSync()
            }
        }
    }

    func syncActiveRoomSettings() {
        guard let activeRoom, let onlineProfile, activeRoom.hostPlayerID == onlineProfile.id else { return }

        Task {
            do {
                let updated = try await roomService.updateRoom(
                    roomID: activeRoom.id,
                    hostPlayerID: onlineProfile.id,
                    playerCount: playerCount,
                    ruleSet: ruleSet
                )
                let invite = roomService.roomInvite(for: updated)
                await MainActor.run {
                    applyRoom(updated, invite: invite)
                }
            } catch {
                await MainActor.run {
                    onlineStatusMessage = error.localizedDescription
                }
            }
        }
    }

    func startGame() {
        if activeRoom != nil && !isHostOfActiveRoom {
            onlineStatusMessage = "Only the room host can start the online hand."
            return
        }

        configurePlayers()
        resetHandState()
        dealHand()
        phase = .bidding
        screen = .table
        currentTurnSeat = nextActiveSeat(after: dealerSeat)
        auctionSummary = "Bidding starts with \(playerName(forSeat: currentTurnSeat))."
        if activeRoom != nil {
            onlineStatusMessage = "Room roster loaded."
        }
        publishMultiplayerAction(.startHand)
        scheduleBotIfNeeded()
    }

    func placeBid(_ contract: Contract, for player: Player) {
        guard phase == .bidding else { return }
        guard canDeviceControl(player) else { return }
        guard player.seat == currentTurnSeat, !passedBidderIDs.contains(player.id) else { return }
        guard canBid(contract, by: player) else { return }

        let bid = Bid(playerID: player.id, contract: contract)
        bids.append(bid)
        currentBid = bid
        declarerID = player.id
        auctionSummary = "\(player.name) bids \(contract.title)"

        if auctionPlayers.count <= 1 {
            completeAuction()
        } else {
            currentTurnSeat = nextAuctionSeat(after: player.seat)
        }
        publishMultiplayerAction(.bid(playerID: player.id, contract: contract))
        scheduleBotIfNeeded()
    }

    func canBid(_ contract: Contract) -> Bool {
        guard let currentPlayer else { return false }
        return canBid(contract, by: currentPlayer)
    }

    func passBid(for player: Player) {
        guard phase == .bidding else { return }
        guard canDeviceControl(player) else { return }
        guard player.seat == currentTurnSeat, !passedBidderIDs.contains(player.id) else { return }
        passedBidderIDs.insert(player.id)
        auctionSummary = "\(player.name) passes"

        if currentBid == nil, auctionPlayers.isEmpty {
            startRaspasy()
        } else if auctionPlayers.count <= 1 {
            completeAuction()
        } else if let nextSeat = nextAuctionSeatOrNil(after: player.seat) {
            currentTurnSeat = nextSeat
        }
        publishMultiplayerAction(.passBid(playerID: player.id))
        scheduleBotIfNeeded()
    }

    func takeTalon() {
        guard phase == .takingTalon else { return }
        guard let declarerID, let declarerIndex = players.firstIndex(where: { $0.id == declarerID }) else { return }
        guard canDeviceControl(players[declarerIndex]) else { return }

        players[declarerIndex].hand.append(contentsOf: talon)
        players[declarerIndex].hand.sort(by: cardSort)
        talon = []
        selectedDiscardIDs = []
        hiddenDiscard = []
        phase = .discarding
        currentTurnSeat = players[declarerIndex].seat
        handSummary = "Choose 2 cards to discard."
        publishMultiplayerAction(.takeTalon(playerID: players[declarerIndex].id))
        scheduleBotIfNeeded()
    }

    func toggleDiscardSelection(_ card: Card) {
        guard phase == .discarding, let declarer, declarer.seat == currentTurnSeat else { return }
        guard canDeviceControl(declarer) else { return }
        if selectedDiscardIDs.contains(card.id) {
            selectedDiscardIDs.remove(card.id)
        } else if selectedDiscardIDs.count < 2 {
            selectedDiscardIDs.insert(card.id)
        }
    }

    func confirmDiscard() {
        guard phase == .discarding, selectedDiscardIDs.count == 2 else { return }
        guard let declarerID, let declarerIndex = players.firstIndex(where: { $0.id == declarerID }) else { return }
        guard canDeviceControl(players[declarerIndex]) else { return }

        let discarded = players[declarerIndex].hand.filter { selectedDiscardIDs.contains($0.id) }
        players[declarerIndex].hand.removeAll { selectedDiscardIDs.contains($0.id) }
        players[declarerIndex].hand.sort(by: cardSort)
        hiddenDiscard = discarded
        selectedDiscardIDs = []

        if currentBid?.contract == .misere {
            declaredContract = .misere
            prepareForPlay()
        } else {
            phase = .declaringContract
            handSummary = "Order the final contract. It cannot be lower than the winning bid."
        }
        publishMultiplayerAction(.discard(playerID: players[declarerIndex].id, cardIDs: discarded.map(\.id).sorted()))
        scheduleBotIfNeeded()
    }

    func declareFinalContract(_ contract: Contract) {
        guard phase == .declaringContract else { return }
        guard let declarer, canDeviceControl(declarer) else { return }
        guard availableFinalContracts.contains(contract) else { return }
        declaredContract = contract
        auctionSummary = "\(playerName(for: declarerID)) orders \(contract.title)"

        if contract == .misere {
            prepareForPlay()
        } else {
            startWhisting()
        }
        publishMultiplayerAction(.declareContract(playerID: declarer.id, contract: contract))
        scheduleBotIfNeeded()
    }

    func chooseWhist(_ decision: WhistDecision, for player: Player) {
        guard phase == .whisting else { return }
        guard canDeviceControl(player) else { return }
        guard player.seat == currentTurnSeat else { return }
        guard defenders.contains(where: { $0.id == player.id }) else { return }
        guard availableWhistOptions(for: player).contains(decision) else { return }

        whistDecisions[player.id] = decision
        handSummary = "\(player.name): \(decision.title)"

        if let nextSeat = nextPendingWhistSeat(after: player.seat) {
            currentTurnSeat = nextSeat
            publishMultiplayerAction(.whist(playerID: player.id, decision: decision))
            scheduleBotIfNeeded()
            return
        }

        finishWhisting()
        publishMultiplayerAction(.whist(playerID: player.id, decision: decision))
        scheduleBotIfNeeded()
    }

    func playCard(_ card: Card, from player: Player) {
        guard phase == .playing else { return }
        guard !isTrickAwaitingCollection else { return }
        guard canDeviceControl(player) else { return }
        guard player.seat == currentTurnSeat, isLegalPlay(card, for: player) else { return }
        guard let playerIndex = players.firstIndex(where: { $0.id == player.id }),
              let cardIndex = players[playerIndex].hand.firstIndex(of: card) else { return }

        players[playerIndex].hand.remove(at: cardIndex)
        activeTrick.append(TrickPlay(playerID: player.id, card: card))

        if activeTrick.count == activePlayers.count {
            let winnerName = playerName(for: winner(for: activeTrick).playerID)
            handSummary = "Trick complete. \(winnerName) takes it. Review the cards, then collect."
        } else {
            currentTurnSeat = nextActiveSeat(after: player.seat)
        }
        publishMultiplayerAction(.playCard(playerID: player.id, card: card))
        scheduleBotIfNeeded()
    }

    func collectCompletedTrick() {
        guard isTrickAwaitingCollection else { return }
        let winningPlayerID = winner(for: activeTrick).playerID
        resolveTrick()
        publishMultiplayerAction(.stateAdvanced(reason: "Collected trick for \(playerName(for: winningPlayerID))"))
        scheduleBotIfNeeded()
    }

    func availableClaimTotals(for player: Player) -> [Int] {
        guard phase == .playing else { return [] }
        let remainingTricks = player.hand.count
        let minimum = player.tricksWon
        let maximum = player.tricksWon + remainingTricks
        guard minimum <= maximum else { return [] }
        return Array(minimum...maximum)
    }

    func proposeClaim(totalTricks: Int) {
        guard phase == .playing, let currentPlayer else { return }
        guard canDeviceControl(currentPlayer) else { return }
        guard availableClaimTotals(for: currentPlayer).contains(totalTricks) else { return }

        var responses: [UUID: ClaimResponse] = [:]
        for player in activePlayers where player.id != currentPlayer.id {
            responses[player.id] = .pending
        }

        trickClaimProposal = TrickClaimProposal(
            proposerID: currentPlayer.id,
            targetPlayerID: currentPlayer.id,
            claimedTotalTricks: totalTricks,
            responses: responses
        )
        handSummary = "\(currentPlayer.name) proposes to stop play and record \(totalTricks) tricks."
        publishMultiplayerAction(.proposeClaim(playerID: currentPlayer.id, totalTricks: totalTricks))
        scheduleBotIfNeeded()
    }

    func respondToClaim(accept: Bool, by player: Player) {
        guard var proposal = trickClaimProposal else { return }
        guard canDeviceControl(player) else { return }
        guard player.id != proposal.proposerID else { return }
        proposal.responses[player.id] = accept ? .accepted : .rejected
        trickClaimProposal = proposal

        if !accept {
            handSummary = "\(player.name) rejected the claim."
            publishMultiplayerAction(.respondToClaim(playerID: player.id, accepted: false))
            return
        }

        let everyoneAccepted = activePlayers
            .filter { $0.id != proposal.proposerID }
            .allSatisfy { proposal.response(for: $0.id) == .accepted }

        if everyoneAccepted {
            applyClaimProposal(proposal)
        }
        publishMultiplayerAction(.respondToClaim(playerID: player.id, accepted: true))
        scheduleBotIfNeeded()
    }

    func counterClaim(with totalTricks: Int, by player: Player) {
        guard var proposal = trickClaimProposal else { return }
        guard canDeviceControl(player) else { return }
        guard player.id != proposal.proposerID else { return }
        guard let targetPlayer = players.first(where: { $0.id == proposal.targetPlayerID }) else { return }
        guard availableClaimTotals(for: targetPlayer).contains(totalTricks) else { return }

        proposal.claimedTotalTricks = totalTricks
        for other in activePlayers where other.id != proposal.proposerID {
            proposal.responses[other.id] = other.id == player.id ? .accepted : .pending
        }
        trickClaimProposal = proposal
        handSummary = "\(player.name) made a counter-proposal: \(totalTricks) tricks."
        publishMultiplayerAction(.counterClaim(playerID: player.id, totalTricks: totalTricks))
        scheduleBotIfNeeded()
    }

    func cancelClaimProposal() {
        if let currentPlayer, !canDeviceControl(currentPlayer) {
            return
        }
        trickClaimProposal = nil
        publishMultiplayerAction(.cancelClaim(playerID: currentPlayer?.id))
        scheduleBotIfNeeded()
    }

    func resetToLobby() {
        botTask?.cancel()
        rotateDealer()
        phase = .setup
        screen = .lobby
        if activeRoom == nil {
            invite = nil
        }
        resetHandState(clearPartySummary: false)
        for index in players.indices {
            players[index].hand = []
            players[index].tricksWon = 0
        }
        configurePlayers()
        publishMultiplayerAction(.resetToLobby)
    }

    func startNextHand() {
        rotateDealer()
        startGame()
    }

    private func resetHandState(clearPartySummary: Bool = true) {
        botTask?.cancel()
        talon = []
        hiddenDiscard = []
        bids = []
        currentBid = nil
        declaredContract = nil
        declarerID = nil
        passedBidderIDs = []
        whistDecisions = [:]
        lightWhistControllerID = nil
        openHandPlayerIDs = []
        selectedDiscardIDs = []
        activeTrick = []
        trickHistory = []
        handSummary = nil
        auctionSummary = nil
        partyBreakdown = []
        trickClaimProposal = nil
        if clearPartySummary {
            partySummary = nil
        }
        for index in players.indices {
            players[index].hand = []
            players[index].tricksWon = 0
        }
    }

    private func dealHand() {
        var deck = Suit.allCases.flatMap { suit in
            Rank.allCases.map { Card(suit: suit, rank: $0) }
        }.shuffled()

        talon = [deck.removeFirst(), deck.removeFirst()]

        let seats = activePlayers.map(\.seat)
        for _ in 0..<10 {
            for seat in seats {
                guard let playerIndex = players.firstIndex(where: { $0.seat == seat }) else { continue }
                players[playerIndex].hand.append(deck.removeFirst())
            }
        }

        for index in players.indices {
            players[index].hand.sort(by: cardSort)
        }
    }

    private func canBid(_ contract: Contract, by player: Player) -> Bool {
        guard phase == .bidding else { return false }
        guard canDeviceControl(player) else { return false }
        guard player.seat == currentTurnSeat else { return false }
        guard !passedBidderIDs.contains(player.id) else { return false }

        let currentStrength = currentBid?.strength ?? -1
        guard contract.strength > currentStrength else { return false }

        if contract == .misere {
            let alreadyBid = bids.contains(where: { $0.playerID == player.id })
            return !alreadyBid
        }

        if bids.contains(where: { $0.playerID == player.id && $0.contract == .misere }) {
            return false
        }

        return contract != .raspasy
    }

    private func completeAuction() {
        guard let currentBid else {
            startRaspasy()
            return
        }
        declarerID = currentBid.playerID
        declaredContract = nil
        phase = .takingTalon
        currentTurnSeat = players.first(where: { $0.id == currentBid.playerID })?.seat ?? 0
        auctionSummary = "Auction won by \(playerName(for: currentBid.playerID)) with \(currentBid.contract.title)"
        handSummary = currentBid.contract == .misere
            ? "Declarer takes the talon, discards 2 cards, then plays misere."
            : "Declarer takes the talon, discards 2 cards, then orders the final contract."
    }

    private func startRaspasy() {
        declaredContract = .raspasy
        declarerID = nil
        phase = .playing
        currentTurnSeat = nextActiveSeat(after: dealerSeat)
        auctionSummary = "Everyone passed. Raspasy."
        handSummary = "No trump. Everyone tries to take as few tricks as possible."
    }

    private func startWhisting() {
        whistDecisions = Dictionary(uniqueKeysWithValues: defenders.map { ($0.id, .undecided) })
        phase = .whisting
        currentTurnSeat = nextActiveSeat(after: players.first(where: { $0.id == declarerID })?.seat ?? dealerSeat)
        handSummary = "Defenders decide whether to whist or pass."
    }

    private func availableWhistOptions(for player: Player) -> [WhistDecision] {
        guard phase == .whisting, defenders.contains(where: { $0.id == player.id }) else { return [] }
        guard let contract = declaredContract else { return [] }
        guard contract.isTrickGame else { return [] }

        let orderedDefenders = defenders.sorted { $0.seat < $1.seat }
        guard let firstDefender = orderedDefenders.first,
              let lastDefender = orderedDefenders.last else {
            return [.pass, .whist]
        }

        if firstDefender.id == player.id {
            return [.pass, .whist]
        }

        if lastDefender.id == player.id,
           whistDecisions[firstDefender.id] == .pass,
           let target = contract.targetTricks,
           target <= 7 {
            return [.pass, .halfWhist, .whist]
        }

        return [.pass, .whist]
    }

    private func nextPendingWhistSeat(after seat: Int) -> Int? {
        let pending = defenders
            .filter { whistDecisions[$0.id] == .undecided }
            .map(\.seat)
            .sorted()
        guard !pending.isEmpty else { return nil }
        if let index = pending.firstIndex(of: seat) {
            return pending[(index + 1) % pending.count]
        }
        return pending.first
    }

    private func finishWhisting() {
        let decisions = defenders.compactMap { defender in
            whistDecisions[defender.id].map { (defender, $0) }
        }

        let whisters = decisions.filter { $0.1 == .whist }.map(\.0)
        let halfWhister = decisions.first(where: { $0.1 == .halfWhist })?.0

        if whisters.isEmpty, let halfWhister {
            settleHalfWhist(for: halfWhister)
            return
        }

        if whisters.isEmpty {
            settleWithoutWhisters()
            return
        }

        if whisters.count == 1 {
            lightWhistControllerID = whisters[0].id
            openHandPlayerIDs = Set(defenders.map(\.id))
            handSummary = "\(whisters[0].name) whists in the light and controls both defending hands."
        } else {
            lightWhistControllerID = nil
            openHandPlayerIDs = []
        }

        prepareForPlay()
    }

    private func settleWithoutWhisters() {
        guard let declarerID, let contract = declaredContract else { return }
        let value = contract.gameValue
        addPool(value, to: declarerID)
        handSummary = "Both defenders passed. Declarer records the contract without play."
        finishHand()
    }

    private func settleHalfWhist(for defender: Player) {
        guard let declarerID, let contract = declaredContract else { return }
        let value = contract.gameValue
        addPool(value, to: declarerID)
        let simulatedDefenderTricks = contract.defenderQuota ?? 0
        recordWhists(from: defender.id, to: declarerID, amount: value * simulatedDefenderTricks)
        handSummary = "\(defender.name) half-whists. The hand is settled without play."
        finishHand()
    }

    private func prepareForPlay() {
        phase = .playing
        if declaredContract == .misere {
            openHandPlayerIDs = Set(defenders.map(\.id))
            lightWhistControllerID = defenders.first?.id
            currentTurnSeat = players.first(where: { $0.id == declarerID })?.seat ?? currentTurnSeat
            handSummary = "Misere: declarer must avoid all tricks."
        } else if declaredContract == .raspasy {
            lightWhistControllerID = nil
            openHandPlayerIDs = []
            currentTurnSeat = nextActiveSeat(after: dealerSeat)
        } else {
            currentTurnSeat = players.first(where: { $0.id == declarerID })?.seat ?? currentTurnSeat
            handSummary = "Play starts. Declarer leads the first trick."
        }
    }

    private func resolveTrick() {
        let winningPlay = winner(for: activeTrick)
        if let winnerIndex = players.firstIndex(where: { $0.id == winningPlay.playerID }) {
            players[winnerIndex].tricksWon += 1
            currentTurnSeat = players[winnerIndex].seat
        }
        trickHistory.append(activeTrick)
        activeTrick = []

        let cardsRemaining = activePlayers.map(\.hand.count).reduce(0, +)
        if cardsRemaining == 0 {
            settlePlayedHand()
        }
    }

    private func settlePlayedHand() {
        trickClaimProposal = nil
        guard let contract = declaredContract else {
            finishHand()
            return
        }

        switch contract {
        case .raspasy:
            settleRaspasy()
        case .misere:
            settleMisere()
        case .suited, .noTrump:
            settleTrickContract(contract)
        }

        finishHand()
    }

    private func settleRaspasy() {
        for player in activePlayers {
            if player.tricksWon == 0 {
                addPool(1, to: player.id)
            } else {
                applyPenalty(points: player.tricksWon, to: player.id)
            }
        }
        handSummary = "Raspasy settled automatically."
    }

    private func settleMisere() {
        guard let declarerID, let declarer = players.first(where: { $0.id == declarerID }) else { return }
        if declarer.tricksWon == 0 {
            addPool(10, to: declarerID)
            handSummary = "\(declarer.name) made misere."
        } else {
            applyPenalty(points: declarer.tricksWon * 10, to: declarerID)
            handSummary = "\(declarer.name) failed misere with \(declarer.tricksWon) trick(s)."
        }
    }

    private func settleTrickContract(_ contract: Contract) {
        guard let declarerID, let declarerIndex = players.firstIndex(where: { $0.id == declarerID }) else { return }

        let value = contract.gameValue
        let declarerTricks = players[declarerIndex].tricksWon
        let target = contract.targetTricks ?? 0
        let defendersTotal = max(0, 10 - declarerTricks)
        let whisters = defenders.filter { whistDecisions[$0.id] == .whist }
        let passingDefenders = defenders.filter { whistDecisions[$0.id] != .whist }

        if declarerTricks >= target {
            addPool(value, to: declarerID)
            if !whisters.isEmpty {
                for defender in whisters {
                    let defenderTricks = players.first(where: { $0.id == defender.id })?.tricksWon ?? 0
                    let payableTricks = whisters.count == 1 ? defendersTotal : defenderTricks
                    recordWhists(from: defender.id, to: declarerID, amount: payableTricks * value)
                }
            }
            handSummary = "\(playerName(for: declarerID)) made \(contract.title)."
        } else {
            let undertricks = target - declarerTricks
            applyPenalty(points: undertricks * value, to: declarerID)
            if whisters.count == 1, let whister = whisters.first, !passingDefenders.isEmpty {
                let splitWhists = defendersTotal * value
                let whisterShare = splitWhists / 2
                let passerShare = splitWhists - whisterShare
                recordWhists(from: whister.id, to: declarerID, amount: whisterShare)
                for passer in passingDefenders {
                    recordWhists(from: passer.id, to: declarerID, amount: passerShare / max(1, passingDefenders.count))
                }
                handSummary = "\(playerName(for: declarerID)) failed \(contract.title). Gentleman whist split between defenders."
            } else {
                for defender in defenders {
                    let defenderTricks = players.first(where: { $0.id == defender.id })?.tricksWon ?? 0
                    if defenderTricks > 0 {
                        recordWhists(from: defender.id, to: declarerID, amount: defenderTricks * value)
                    }
                }
                handSummary = "\(playerName(for: declarerID)) failed \(contract.title) by \(undertricks)."
            }
        }

        if !whisters.isEmpty, let quota = contract.defenderQuota {
            let missing = max(0, quota - defendersTotal)
            if missing > 0 {
                distributeWhisterPenalty(whisters: whisters, points: missing * value)
            }
        }
    }

    private func distributeWhisterPenalty(whisters: [Player], points: Int) {
        guard !whisters.isEmpty else { return }

        if ruleSet == .rostov {
            for whister in whisters {
                let share = max(1, points / max(1, whisters.count))
                for opponent in activePlayers where opponent.id != whister.id {
                    recordWhists(from: opponent.id, to: whister.id, amount: share * 5)
                }
            }
            return
        }

        for whister in whisters {
            let share = max(1, points / max(1, whisters.count))
            applyPenalty(points: share, to: whister.id)
        }
    }

    private func finishHand() {
        phase = .handFinished
        trickClaimProposal = nil
        botTask?.cancel()
        recalculateDisplayScores()
        applyAmericanAidIfNeeded()
        recalculateDisplayScores()

        if hasFinishedParty {
            let settlement = buildPartySettlement()
            partySummary = settlement.summary
            partyBreakdown = settlement.breakdown
        }
    }

    private func addPool(_ amount: Int, to playerID: UUID) {
        guard let index = players.firstIndex(where: { $0.id == playerID }) else { return }
        players[index].pool += amount
    }

    private func applyClaimProposal(_ proposal: TrickClaimProposal) {
        guard let targetIndex = players.firstIndex(where: { $0.id == proposal.targetPlayerID }) else { return }

        let remainingTricks = activePlayers.first?.hand.count ?? 0
        let claimedAdditional = max(0, proposal.claimedTotalTricks - players[targetIndex].tricksWon)
        let awardedToTarget = min(remainingTricks, claimedAdditional)
        players[targetIndex].tricksWon += awardedToTarget

        var tricksLeft = remainingTricks - awardedToTarget
        let others = activePlayers.filter { $0.id != proposal.targetPlayerID }.sorted { $0.seat < $1.seat }
        var cursor = 0
        while tricksLeft > 0, !others.isEmpty {
            if let otherIndex = players.firstIndex(where: { $0.id == others[cursor].id }) {
                players[otherIndex].tricksWon += 1
            }
            tricksLeft -= 1
            cursor = (cursor + 1) % others.count
        }

        for index in players.indices {
            players[index].hand = []
        }
        activeTrick = []
        trickHistory = []
        trickClaimProposal = nil
        handSummary = "\(playerName(for: proposal.proposerID))'s claim was accepted."
        settlePlayedHand()
    }

    private func scheduleBotIfNeeded() {
        botTask?.cancel()
        guard shouldBotAct else { return }

        botTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.performBotActionIfNeeded()
            }
        }
    }

    private var shouldBotAct: Bool {
        if isTrickAwaitingCollection {
            return false
        }

        if let proposal = trickClaimProposal {
            return activePlayers.contains { player in
                player.id != proposal.proposerID &&
                proposal.response(for: player.id) == .pending &&
                isBotControlled(player)
            }
        }

        guard screen == .table else { return false }
        guard let currentPlayer else { return false }
        return isBotControlled(currentPlayer)
    }

    private func isBotControlled(_ player: Player) -> Bool {
        if activeRoom != nil {
            if activeRoom?.participants.contains(where: { $0.seat == player.seat }) == true {
                return false
            }
            return isHostOfActiveRoom
        }

        if player.seat == localSeat { return false }
        if phase == .playing,
           lightWhistControllerID == localPlayer?.id,
           defenders.contains(where: { $0.id == player.id }) {
            return false
        }
        return true
    }

    private func performBotActionIfNeeded() {
        if let proposal = trickClaimProposal,
           let responder = activePlayers.first(where: {
               $0.id != proposal.proposerID &&
               proposal.response(for: $0.id) == .pending &&
               isBotControlled($0)
           }) {
            respondToClaim(accept: true, by: responder)
            return
        }

        guard let player = currentPlayer, isBotControlled(player) else { return }

        switch phase {
        case .bidding:
            performBotBid(for: player)
        case .takingTalon:
            takeTalon()
        case .discarding:
            performBotDiscard(for: player)
        case .declaringContract:
            performBotFinalDeclaration(for: player)
        case .whisting:
            performBotWhist(for: player)
        case .playing:
            performBotPlay(for: player)
        case .setup, .handFinished:
            break
        }
    }

    private func performBotBid(for player: Player) {
        if canBid(.misere, by: player), handLooksLikeMisere(player.hand) {
            placeBid(.misere, for: player)
            return
        }

        let viable = availableContracts.filter { contract in
            bidConfidence(for: contract, hand: player.hand) >= bidThreshold(for: contract)
        }

        if let choice = viable.max(by: { $0.strength < $1.strength }) {
            placeBid(choice, for: player)
        } else {
            passBid(for: player)
        }
    }

    private func performBotDiscard(for player: Player) {
        let chosen = botDiscardCards(for: player)
        selectedDiscardIDs = Set(chosen.map(\.id))
        confirmDiscard()
    }

    private func performBotFinalDeclaration(for player: Player) {
        let ranked = availableFinalContracts
            .filter { contract in
                bidConfidence(for: contract, hand: player.hand) >= bidThreshold(for: contract) - 0.5
            }

        declareFinalContract(
            ranked.max(by: { $0.strength < $1.strength }) ??
            currentBid?.contract ??
            availableFinalContracts.first ??
            .noTrump(tricks: 6)
        )
    }

    private func performBotWhist(for player: Player) {
        let options = availableWhistOptions(for: player)
        let handPower = trickTakingPotential(for: player.hand)

        if options.contains(.whist), handPower >= 7 {
            chooseWhist(.whist, for: player)
        } else if options.contains(.halfWhist), handPower >= 5 {
            chooseWhist(.halfWhist, for: player)
        } else {
            chooseWhist(.pass, for: player)
        }
    }

    private func performBotPlay(for player: Player) {
        let legalCards = player.hand.filter { isLegalPlay($0, for: player) }
        guard !legalCards.isEmpty else { return }

        let chosen: Card
        if wantsToAvoidTricks(player) {
            chosen = chooseSafestCard(from: legalCards, for: player)
        } else {
            chosen = chooseAggressiveCard(from: legalCards, for: player)
        }

        playCard(chosen, from: player)
    }

    private func chooseAggressiveCard(from legalCards: [Card], for player: Player) -> Card {
        let winners = legalCards.filter { card in
            cardWouldWinTrick(card, for: player)
        }
        if let cheapestWinner = winners.min(by: cardSortAscending) {
            return cheapestWinner
        }
        return legalCards.min(by: cardSortAscending) ?? legalCards[0]
    }

    private func chooseSafestCard(from legalCards: [Card], for player: Player) -> Card {
        let nonWinners = legalCards.filter { !cardWouldWinTrick($0, for: player) }
        if let safest = nonWinners.min(by: cardSortAscending) {
            return safest
        }
        return legalCards.min(by: cardSortAscending) ?? legalCards[0]
    }

    private func cardWouldWinTrick(_ card: Card, for player: Player) -> Bool {
        let simulated = activeTrick + [TrickPlay(playerID: player.id, card: card)]
        return winner(for: simulated).playerID == player.id
    }

    private func wantsToAvoidTricks(_ player: Player) -> Bool {
        if declaredContract == .raspasy { return true }
        if declaredContract == .misere { return player.id == declarerID }
        return false
    }

    private func botDiscardCards(for player: Player) -> [Card] {
        let currentContract = currentBid?.contract ?? .noTrump(tricks: 6)
        let suitCounts = Dictionary(grouping: player.hand, by: \.suit).mapValues(\.count)

        switch currentContract {
        case .misere:
            return player.hand
                .sorted { misereDanger($0, suitCounts: suitCounts) > misereDanger($1, suitCounts: suitCounts) }
                .prefix(2)
                .map { $0 }
        case let .suited(_, trump):
            return player.hand
                .sorted {
                    discardValue($0, trump: trump, suitCounts: suitCounts) <
                    discardValue($1, trump: trump, suitCounts: suitCounts)
                }
                .prefix(2)
                .map { $0 }
        case .noTrump:
            return player.hand
                .sorted {
                    discardValue($0, trump: nil, suitCounts: suitCounts) <
                    discardValue($1, trump: nil, suitCounts: suitCounts)
                }
                .prefix(2)
                .map { $0 }
        case .raspasy:
            return Array(player.hand.prefix(2))
        }
    }

    private func trickTakingPotential(for hand: [Card]) -> Double {
        hand.reduce(0) { partial, card in
            partial + honorValue(for: card.rank)
        }
    }

    private func bidConfidence(for contract: Contract, hand: [Card]) -> Double {
        let suitCounts = Dictionary(grouping: hand, by: \.suit)
        let totalHonors = trickTakingPotential(for: hand)
        let aces = hand.filter { $0.rank == .ace }.count

        switch contract {
        case let .suited(_, trump):
            let trumpCards = suitCounts[trump] ?? []
            let trumpPower = trumpCards.reduce(0) { $0 + honorValue(for: $1.rank) } + Double(trumpCards.count) * 0.9
            return totalHonors * 0.42 + trumpPower
        case .noTrump:
            return totalHonors * 0.62 + Double(aces) * 0.9
        case .misere:
            return handLooksLikeMisere(hand) ? 100 : 0
        case .raspasy:
            return 0
        }
    }

    private func bidThreshold(for contract: Contract) -> Double {
        switch contract {
        case let .suited(tricks, _):
            switch tricks {
            case 6: return 5.2
            case 7: return 6.6
            case 8: return 8.0
            case 9: return 9.8
            case 10: return 11.2
            default: return 12.0
            }
        case let .noTrump(tricks):
            switch tricks {
            case 6: return 6.2
            case 7: return 7.6
            case 8: return 9.0
            case 9: return 10.6
            case 10: return 12.0
            default: return 12.5
            }
        case .misere: return 100
        case .raspasy: return .infinity
        }
    }

    private func handLooksLikeMisere(_ hand: [Card]) -> Bool {
        let bigCards = hand.filter { $0.rank.rawValue >= Rank.queen.rawValue }.count
        let aces = hand.filter { $0.rank == .ace }.count
        let tensOrHigher = hand.filter { $0.rank.rawValue >= Rank.ten.rawValue }.count
        return aces == 0 && bigCards <= 2 && tensOrHigher <= 4
    }

    private func discardValue(_ card: Card, trump: Suit?, suitCounts: [Suit: Int]) -> Double {
        var score = honorValue(for: card.rank)
        if card.suit == trump { score += 4 }
        score += Double(suitCounts[card.suit] ?? 0) * 0.35
        return score
    }

    private func misereDanger(_ card: Card, suitCounts: [Suit: Int]) -> Double {
        Double(card.rank.rawValue) + Double(suitCounts[card.suit] ?? 0) * 0.3
    }

    private func honorValue(for rank: Rank) -> Double {
        switch rank {
        case .ace: return 4
        case .king: return 3
        case .queen: return 2
        case .jack: return 1
        case .ten: return 0.6
        case .nine: return 0.2
        case .eight, .seven: return 0
        }
    }

    private func cardSortAscending(_ lhs: Card, _ rhs: Card) -> Bool {
        if lhs.suit.rank == rhs.suit.rank {
            return lhs.rank.rawValue < rhs.rank.rawValue
        }
        return lhs.suit.rank < rhs.suit.rank
    }

    private func joinRoom(using code: String) {
        guard let onlineProfile else {
            pendingInviteCode = code
            onlineStatusMessage = "Sign in before joining a room."
            return
        }

        Task {
            do {
                let room = try await roomService.joinRoom(code: code, player: onlineProfile)
                let invite = roomService.roomInvite(for: room)
                await MainActor.run {
                    applyRoom(room, invite: invite)
                    pendingInviteCode = nil
                    joinLinkInput = ""
                    onlineStatusMessage = "Joined room \(room.code)."
                }
            } catch {
                await MainActor.run {
                    onlineStatusMessage = error.localizedDescription
                }
            }
        }
    }

    private func applyRoom(_ room: OnlineRoom, invite: RoomInvite?) {
        activeRoom = room
        self.invite = invite
        playerCount = room.playerCount
        ruleSet = room.ruleSet
        syncDisplayNames()
        configurePlayers()
        startRoomSync()
    }

    private func restoreOnlineProfile() {
        guard let data = UserDefaults.standard.data(forKey: StorageKey.onlineProfile),
              let profile = try? JSONDecoder().decode(OnlineProfile.self, from: data) else {
            return
        }
        onlineProfile = profile
    }

    private func persistOnlineProfile() {
        guard let onlineProfile,
              let data = try? JSONEncoder().encode(onlineProfile) else { return }
        UserDefaults.standard.set(data, forKey: StorageKey.onlineProfile)
    }

    private func syncDisplayNames() {
        let baseNames = ["You", "Mila", "Leo", "Nika"]

        for index in players.indices {
            players[index].name = baseNames[index]
        }

        if let activeRoom {
            for participant in activeRoom.sortedParticipants {
                guard let index = players.firstIndex(where: { $0.seat == participant.seat }) else { continue }
                players[index].name = participant.displayName
            }
            return
        }

        if let onlineProfile,
           let index = players.firstIndex(where: { $0.seat == localSeat }) {
            players[index].name = onlineProfile.displayName
        }
    }

    private func startRoomSync() {
        roomSyncTask?.cancel()
        guard activeRoom != nil, onlineProfile != nil else { return }

        roomSyncTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshRemoteRoomState()

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                await self.refreshRemoteRoomState()
            }
        }
    }

    private func stopRoomSync() {
        roomSyncTask?.cancel()
        roomSyncTask = nil
        snapshotPushTask?.cancel()
        snapshotPushTask = nil
    }

    private func refreshRemoteRoomState() async {
        guard let activeRoom else { return }

        do {
            let latestRoom = try await roomService.fetchRoom(roomID: activeRoom.id)
            let latestSnapshot = try await roomService.fetchSnapshot(roomID: activeRoom.id)

            await MainActor.run {
                let invite = roomService.roomInvite(for: latestRoom)
                if latestRoom != self.activeRoom {
                    self.activeRoom = latestRoom
                    self.invite = invite
                    self.playerCount = latestRoom.playerCount
                    self.ruleSet = latestRoom.ruleSet
                    self.syncDisplayNames()
                }

                guard let latestSnapshot else { return }
                guard latestSnapshot.revision > lastAppliedSnapshotRevision else { return }

                if latestSnapshot.updatedByPlayerID == onlineProfile?.id {
                    lastAppliedSnapshotRevision = latestSnapshot.revision
                } else {
                    applyMultiplayerState(latestSnapshot.state)
                    lastAppliedSnapshotRevision = latestSnapshot.revision
                    multiplayerSyncStatus = "Received room snapshot rev \(latestSnapshot.revision)"
                }
            }
        } catch {
            await MainActor.run {
                multiplayerSyncStatus = error.localizedDescription
            }
        }
    }

    private func publishMultiplayerAction(_ action: MultiplayerGameAction) {
        snapshotPushTask?.cancel()
        guard let room = activeRoom, let onlineProfile else { return }
        guard !isApplyingRemoteSnapshot else { return }

        let snapshot = MultiplayerGameSnapshot(
            roomID: room.id,
            revision: lastAppliedSnapshotRevision + 1,
            updatedByPlayerID: onlineProfile.id,
            updatedAt: .now,
            state: makeMultiplayerState()
        )

        snapshotPushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self else { return }
            guard !Task.isCancelled else { return }

            do {
                guard let room = self.activeRoom else { return }
                let saved = try await roomService.saveSnapshot(snapshot, for: room)
                await MainActor.run {
                    self.lastAppliedSnapshotRevision = saved.revision
                    self.multiplayerSyncStatus = "Synced room snapshot rev \(saved.revision)"
                }
            } catch {
                await self.refreshRemoteRoomState()
                await MainActor.run {
                    self.multiplayerSyncStatus = error.localizedDescription
                }
            }
        }
    }

    private func makeMultiplayerEvent(_ action: MultiplayerGameAction) -> MultiplayerGameEvent {
        let revision = lastAppliedSnapshotRevision + 1
        return MultiplayerGameEvent(
            id: "\(activeRoom?.id ?? "local")-event-\(revision)",
            roomID: activeRoom?.id ?? "",
            revision: revision,
            actorPlayerID: onlineProfile?.id ?? "local",
            createdAt: .now,
            action: action,
            resultingState: makeMultiplayerState()
        )
    }

    private func makeMultiplayerState() -> MultiplayerGameState {
        MultiplayerGameState(
            screen: screen,
            playerCount: playerCount,
            ruleSet: ruleSet,
            players: players,
            dealerSeat: dealerSeat,
            phase: phase,
            talon: talon,
            hiddenDiscard: hiddenDiscard,
            selectedDiscardIDs: Array(selectedDiscardIDs).sorted(),
            bids: bids.map { SnapshotBid(playerID: $0.playerID, contract: $0.contract) },
            currentBid: currentBid.map { SnapshotBid(playerID: $0.playerID, contract: $0.contract) },
            declaredContract: declaredContract,
            declarerID: declarerID,
            passedBidderIDs: passedBidderIDs.map { SnapshotPassedBidder(playerID: $0) },
            auctionSummary: auctionSummary,
            whistDecisions: whistDecisions.map { SnapshotWhistDecision(playerID: $0.key, decision: $0.value) },
            lightWhistControllerID: lightWhistControllerID,
            openHandPlayerIDs: openHandPlayerIDs.map { SnapshotOpenHand(playerID: $0) },
            activeTrick: activeTrick.map { SnapshotTrickPlay(playerID: $0.playerID, card: $0.card) },
            trickHistory: trickHistory.map { trick in
                trick.map { SnapshotTrickPlay(playerID: $0.playerID, card: $0.card) }
            },
            currentTurnSeat: currentTurnSeat,
            handSummary: handSummary,
            partySummary: partySummary,
            partyBreakdown: partyBreakdown,
            trickClaimProposal: trickClaimProposal.map { proposal in
                SnapshotClaimProposal(
                    proposerID: proposal.proposerID,
                    targetPlayerID: proposal.targetPlayerID,
                    claimedTotalTricks: proposal.claimedTotalTricks,
                    responses: proposal.responses.map { SnapshotClaimResponse(playerID: $0.key, response: $0.value) }
                )
            },
            whistLedger: whistLedger.flatMap { writerID, entries in
                entries.map { targetID, amount in
                    SnapshotWhistLedgerEntry(writerID: writerID, targetID: targetID, amount: amount)
                }
            }
        )
    }

    private func applyMultiplayerEvent(_ event: MultiplayerGameEvent) {
        isApplyingRemoteSnapshot = true
        defer { isApplyingRemoteSnapshot = false }

        lastAppliedSnapshotRevision = event.revision
        multiplayerSyncStatus = "Received event rev \(event.revision)"
        applyMultiplayerState(event.resultingState)
    }

    private func applyMultiplayerState(_ state: MultiplayerGameState) {
        screen = state.screen
        playerCount = state.playerCount
        ruleSet = state.ruleSet
        players = state.players
        dealerSeat = state.dealerSeat
        phase = state.phase
        talon = state.talon
        hiddenDiscard = state.hiddenDiscard
        selectedDiscardIDs = Set(state.selectedDiscardIDs)
        bids = state.bids.map { Bid(playerID: $0.playerID, contract: $0.contract) }
        currentBid = state.currentBid.map { Bid(playerID: $0.playerID, contract: $0.contract) }
        declaredContract = state.declaredContract
        declarerID = state.declarerID
        passedBidderIDs = Set(state.passedBidderIDs.map(\.playerID))
        auctionSummary = state.auctionSummary
        whistDecisions = Dictionary(uniqueKeysWithValues: state.whistDecisions.map { ($0.playerID, $0.decision) })
        lightWhistControllerID = state.lightWhistControllerID
        openHandPlayerIDs = Set(state.openHandPlayerIDs.map(\.playerID))
        activeTrick = state.activeTrick.map { TrickPlay(playerID: $0.playerID, card: $0.card) }
        trickHistory = state.trickHistory.map { trick in
            trick.map { TrickPlay(playerID: $0.playerID, card: $0.card) }
        }
        currentTurnSeat = state.currentTurnSeat
        handSummary = state.handSummary
        partySummary = state.partySummary
        partyBreakdown = state.partyBreakdown
        trickClaimProposal = state.trickClaimProposal.map { proposal in
            TrickClaimProposal(
                proposerID: proposal.proposerID,
                targetPlayerID: proposal.targetPlayerID,
                claimedTotalTricks: proposal.claimedTotalTricks,
                responses: Dictionary(uniqueKeysWithValues: proposal.responses.map { ($0.playerID, $0.response) })
            )
        }
        whistLedger = state.whistLedger.reduce(into: [:]) { partial, entry in
            partial[entry.writerID, default: [:]][entry.targetID] = entry.amount
        }
        syncDisplayNames()
        scheduleBotIfNeeded()
    }

    private func applyPenalty(points: Int, to playerID: UUID) {
        if ruleSet == .rostov {
            for opponent in activePlayers where opponent.id != playerID {
                recordWhists(from: opponent.id, to: playerID, amount: points * 5)
            }
            return
        }

        guard let index = players.firstIndex(where: { $0.id == playerID }) else { return }
        players[index].mountain += ruleSet.recordedMountain(points)
    }

    private func recordWhists(from writerID: UUID, to targetID: UUID, amount: Int) {
        guard writerID != targetID else { return }
        let recorded = ruleSet.recordedWhists(amount)
        guard recorded > 0 else { return }
        var writerLedger = whistLedger[writerID, default: [:]]
        writerLedger[targetID, default: 0] += recorded
        whistLedger[writerID] = writerLedger
    }

    private func applyAmericanAidIfNeeded() {
        while let donorIndex = activePlayers
            .compactMap({ player in players.firstIndex(where: { $0.id == player.id && $0.pool > ruleSet.targetPool }) })
            .first {
            let overflow = players[donorIndex].pool - ruleSet.targetPool
            guard overflow > 0 else { break }

            if let recipientIndex = players.indices
                .filter({ !players[$0].isSittingOut && players[$0].pool < ruleSet.targetPool && $0 != donorIndex })
                .max(by: { players[$0].pool < players[$1].pool }) {
                let transfer = min(overflow, ruleSet.targetPool - players[recipientIndex].pool)
                players[donorIndex].pool -= transfer
                players[recipientIndex].pool += transfer
                recordWhists(from: players[donorIndex].id, to: players[recipientIndex].id, amount: transfer * 10)
            } else {
                players[donorIndex].pool = ruleSet.targetPool
                players[donorIndex].mountain = max(0, players[donorIndex].mountain - overflow)
            }
        }
    }

    private func buildPartySettlement() -> (summary: String, breakdown: [String]) {
        let active = activePlayers
        let minMountain = active.map(\.mountain).min() ?? 0
        let ranked = active.map { player -> (String, Int, Int, Int, Int, Int) in
            let outgoing = whistLedger[player.id]?.values.reduce(0, +) ?? 0
            let incoming = whistLedger.values.reduce(0) { partial, ledger in
                partial + (ledger[player.id] ?? 0)
            }
            let bulletWorth = ruleSet == .leningrad ? player.pool * 20 : player.pool * 10
            let amnestiedMountain = max(0, player.mountain - minMountain)
            let net = bulletWorth + outgoing - incoming - amnestiedMountain * 10
            return (player.name, net, player.pool, player.mountain, outgoing - incoming, amnestiedMountain)
        }
        .sorted { $0.1 > $1.1 }

        let lines = ranked.map { "\($0.0): \($0.1)" }
        let breakdown = ranked.map { item in
            "\(item.0) • pool \(item.2) • mountain \(item.3) -> \(item.5) after amnesty • whists \(item.4) • final \(item.1)"
        }
        return ("Party finished (\(ruleSet.title)). " + lines.joined(separator: " • "), breakdown)
    }

    private func recalculateDisplayScores() {
        for index in players.indices {
            let playerID = players[index].id
            let outgoing = whistLedger[playerID]?.values.reduce(0, +) ?? 0
            let incoming = whistLedger.values.reduce(0) { partial, ledger in
                partial + (ledger[playerID] ?? 0)
            }
            let bulletWorth = players[index].pool * 10
            players[index].score = bulletWorth + outgoing - incoming - players[index].mountain * 10
        }
    }

    private func resetWhistLedger() {
        var fresh: [UUID: [UUID: Int]] = [:]
        let ids = players.map(\.id)
        for writer in ids {
            fresh[writer] = [:]
        }
        whistLedger = fresh
    }

    private func rotateDealer() {
        dealerSeat = (dealerSeat + 1) % playerCount
        configurePlayers()
    }

    private func nextAuctionSeat(after seat: Int) -> Int {
        nextAuctionSeatOrNil(after: seat) ?? nextActiveSeat(after: seat)
    }

    private func nextAuctionSeatOrNil(after seat: Int) -> Int? {
        let candidateSeats = auctionPlayers.map(\.seat).sorted()
        guard !candidateSeats.isEmpty else { return nil }
        if let currentIndex = candidateSeats.firstIndex(of: seat) {
            return candidateSeats[(currentIndex + 1) % candidateSeats.count]
        }
        return candidateSeats.first
    }

    private func nextActiveSeat(after seat: Int) -> Int {
        let activeSeats = activePlayers.map(\.seat).sorted()
        guard let currentIndex = activeSeats.firstIndex(of: seat) else {
            return activeSeats.first ?? 0
        }
        return activeSeats[(currentIndex + 1) % activeSeats.count]
    }

    private func winner(for trick: [TrickPlay]) -> TrickPlay {
        let leadSuit = trick.first!.card.suit
        return trick.max { lhs, rhs in
            compare(lhs.card, rhs.card, leadSuit: leadSuit) == .orderedAscending
        }!
    }

    private func compare(_ left: Card, _ right: Card, leadSuit: Suit) -> ComparisonResult {
        let trump = currentTrump
        if left.suit == right.suit {
            return left.rank.rawValue < right.rank.rawValue ? .orderedAscending : .orderedDescending
        }
        if let trump {
            if left.suit == trump { return .orderedDescending }
            if right.suit == trump { return .orderedAscending }
        }
        if left.suit == leadSuit { return .orderedDescending }
        if right.suit == leadSuit { return .orderedAscending }
        return .orderedSame
    }

    private func isLegalPlay(_ card: Card, for player: Player) -> Bool {
        guard let leadSuit = activeTrick.first?.card.suit else { return true }
        if player.hand.contains(where: { $0.suit == leadSuit }) {
            return card.suit == leadSuit
        }
        if let trump = currentTrump, player.hand.contains(where: { $0.suit == trump }) {
            return card.suit == trump
        }
        return true
    }

    private func canLocalUserControl(_ player: Player) -> Bool {
        if activeRoom == nil {
            if player.seat == localSeat { return true }
            if phase == .playing,
               lightWhistControllerID == localPlayer?.id,
               defenders.contains(where: { $0.id == player.id }) {
                return true
            }
            return false
        }

        if player.seat == localSeat { return true }
        if phase == .playing,
           lightWhistControllerID == localPlayer?.id,
           defenders.contains(where: { $0.id == player.id }) {
            return true
        }
        return false
    }

    private func canDeviceControl(_ player: Player) -> Bool {
        canLocalUserControl(player) || isBotControlled(player)
    }

    private func cardSort(_ lhs: Card, _ rhs: Card) -> Bool {
        if lhs.suit.rank == rhs.suit.rank {
            return lhs.rank.rawValue > rhs.rank.rawValue
        }
        return lhs.suit.rank > rhs.suit.rank
    }

    private func playerName(for id: UUID?) -> String {
        guard let id else { return "Player" }
        return players.first(where: { $0.id == id })?.name ?? "Player"
    }

    private func playerName(forSeat seat: Int) -> String {
        players.first(where: { $0.seat == seat })?.name ?? "Player"
    }
}
