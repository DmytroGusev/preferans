import Foundation
import SnapshotTesting
import Testing
@testable import PreferansApp
@testable import PreferansEngine

/// Structural snapshots for important table screens. These are not pixel
/// snapshots; they lock the table-screen contract that must not drift
/// unexpectedly: viewer, clockwise seat placement, auction order, talon
/// visibility, bottom hand owner, and trick-card offsets.
@Suite("Table screen snapshots", .snapshots(record: .missing))
struct TableScreenSnapshotTests {
    private static let tableID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let players: [PlayerID] = ["north", "east", "south"]
    private let layout = TableLayoutModel(bounds: CGSize(width: 368, height: 520))

    @Test func biddingEastViewerKeepsClockwiseTableOrder() throws {
        let engine = try makeFreshDealEngine()
        try assertScreen(engine: engine, viewer: "east")
    }

    @Test func talonExchangeDefenderViewKeepsPublicPrikupScreen() throws {
        let engine = try makeAwaitingDiscardEngine()
        try assertScreen(engine: engine, viewer: "east")
    }

    @Test func midTrickDefenderViewKeepsTrickPlacement() throws {
        let engine = try makeMidTrickEngine()
        try assertScreen(engine: engine, viewer: "east")
    }

    private func assertScreen(
        engine: PreferansEngine,
        viewer: PlayerID,
        fileID: StaticString = #fileID,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        let projection = PlayerProjectionBuilder.projection(
            for: viewer,
            tableID: Self.tableID,
            sequence: 0,
            engine: engine,
            policy: .online
        )
        assertSnapshot(
            of: screenContract(for: projection),
            as: .lines,
            named: viewer.rawValue,
            fileID: fileID,
            file: file,
            testName: testName,
            line: line,
            column: column
        )
    }

    private func screenContract(for projection: PlayerGameProjection) -> String {
        let opponents = projection.tableClockwiseOpponentSeats
        let activeOpponents = opponents.filter { $0.role != .sittingOut }
        let slots = layout.opponentSlots(opponents: activeOpponents)
        let playArea = layout.playArea(for: activeOpponents)
        var lines: [String] = [
            "viewer: \(projection.viewer.rawValue)",
            "phase: \(phaseToken(projection.phase))",
            "players: \(projection.players.map(\.rawValue).joined(separator: " -> "))",
            "bottom: \(handLine(for: projection.viewer, in: projection))",
            "play-area: size=\(sizeToken(playArea.size)) center=\(pointToken(playArea.position))",
            "opponent-slots:"
        ]

        if slots.isEmpty {
            lines.append("  none")
        } else {
            lines.append(contentsOf: slots.map(slotLine))
        }

        let sittingOut = opponents.filter { $0.role == .sittingOut }
        lines.append("sitting-out: \(sittingOut.map { playerToken($0.player, in: projection) }.joined(separator: ", ").nilIfEmpty ?? "none")")
        lines.append("auction:")
        lines.append(contentsOf: projection.tableClockwiseAuctionSeats.map { auctionLine($0, in: projection) })
        lines.append("trick:")
        lines.append(contentsOf: trickLines(for: projection, opponents: activeOpponents.map(\.player)))
        lines.append("talon: \(cardsToken(projection.talon))")
        lines.append("discard: \(cardsToken(projection.discard))")
        lines.append("legal-owner: \(projection.legal.playableCardsOwner?.rawValue ?? projection.viewer.rawValue)")
        lines.append("legal-cards: \(projection.legal.playableCards.map(\.description).joined(separator: " ").nilIfEmpty ?? "none")")

        return lines.joined(separator: "\n")
    }

    private func slotLine(_ slot: TableLayoutModel.OpponentSlot) -> String {
        [
            "  \(seatToken(slot.seat))",
            "orientation=\(orientationToken(slot.orientation))",
            "kind=\(kindToken(slot.kind))",
            "pos=\(pointToken(slot.position))",
            "frame=\(sizeToken(layout.slotFrameSize(for: slot)))",
            "hand=\(handToken(slot.seat.hand))",
            "tricks=\(slot.seat.trickCount)"
        ].joined(separator: " ")
    }

    private func auctionLine(_ seat: SeatProjection, in projection: PlayerGameProjection) -> String {
        let action = projection.auction.last(where: { $0.player == seat.player })
        return [
            "  \(seatToken(seat))",
            "current=\(seat.isCurrentActor)",
            "last=\(action.map { bidCallToken($0.call) } ?? "-")"
        ].joined(separator: " ")
    }

    private func trickLines(for projection: PlayerGameProjection, opponents: [PlayerID]) -> [String] {
        guard !projection.currentTrick.isEmpty else { return ["  none"] }
        return projection.currentTrick.map { play in
            let offset = TableLayoutModel.trickOffset(
                for: play.player,
                viewer: projection.viewer,
                opponents: opponents
            )
            return "  \(playerToken(play.player, in: projection)) card=\(play.card.description) offset=\(sizeToken(offset))"
        }
    }

    private func handLine(for player: PlayerID, in projection: PlayerGameProjection) -> String {
        guard let seat = projection.seats.first(where: { $0.player == player }) else {
            return "\(player.rawValue) missing"
        }
        return "\(playerToken(player, in: projection)) role=\(seat.role.rawValue) hand=\(handToken(seat.hand))"
    }

    private func seatToken(_ seat: SeatProjection) -> String {
        "\(seat.player.rawValue)(role=\(seat.role.rawValue),current=\(seat.isCurrentActor),dealer=\(seat.isDealer))"
    }

    private func playerToken(_ player: PlayerID, in projection: PlayerGameProjection) -> String {
        let order = projection.players.firstIndex(of: player).map { "\($0 + 1)" } ?? "?"
        return "\(order):\(player.rawValue)"
    }

    private func handToken(_ cards: [ProjectedCard]) -> String {
        let known = cards.compactMap(\.knownCard)
        if known.isEmpty { return "hidden:\(cards.count)" }
        return "known:\(known.count)/\(cards.count)[\(known.map(\.description).joined(separator: " "))]"
    }

    private func cardsToken(_ cards: [ProjectedCard]) -> String {
        guard !cards.isEmpty else { return "none" }
        return cards.map { card in
            switch card {
            case let .known(known): return known.description
            case .hidden: return "hidden"
            }
        }.joined(separator: " ")
    }

    private func phaseToken(_ phase: ProjectedPhase) -> String {
        switch phase {
        case let .waitingForDeal(nextDealer):
            return "waitingForDeal nextDealer=\(nextDealer.rawValue)"
        case let .bidding(currentPlayer, highestBid):
            return "bidding current=\(currentPlayer.rawValue) highest=\(highestBid?.description ?? "-")"
        case let .awaitingDiscard(declarer, finalBid):
            return "awaitingDiscard declarer=\(declarer.rawValue) finalBid=\(finalBid.description)"
        case let .awaitingContract(declarer, finalBid):
            return "awaitingContract declarer=\(declarer.rawValue) finalBid=\(finalBid.description)"
        case let .awaitingWhist(currentPlayer, declarer, contract):
            return "awaitingWhist current=\(currentPlayer.rawValue) declarer=\(declarer.rawValue) contract=\(contract.description)"
        case let .awaitingDefenderMode(whister, contract):
            return "awaitingDefenderMode whister=\(whister.rawValue) contract=\(contract.description)"
        case let .playing(currentPlayer, leader, kind):
            return "playing current=\(currentPlayer.rawValue) leader=\(leader.rawValue) kind=\(playKindToken(kind))"
        case let .dealFinished(result):
            return "dealFinished kind=\(result.kind)"
        case .gameOver:
            return "gameOver"
        }
    }

    private func playKindToken(_ kind: ProjectedPlayKind) -> String {
        switch kind {
        case let .game(declarer, contract, defenders, whisters, defenderPlayMode):
            return [
                "game",
                "declarer=\(declarer.rawValue)",
                "contract=\(contract.description)",
                "defenders=\(defenders.map(\.rawValue).joined(separator: "+"))",
                "whisters=\(whisters.map(\.rawValue).joined(separator: "+"))",
                "mode=\(defenderModeToken(defenderPlayMode))"
            ].joined(separator: " ")
        case let .misere(declarer):
            return "misere declarer=\(declarer.rawValue)"
        case .allPass:
            return "allPass"
        }
    }

    private func bidCallToken(_ call: BidCall) -> String {
        switch call {
        case .pass: return "pass"
        case let .bid(bid): return bid.description
        }
    }

    private func defenderModeToken(_ mode: DefenderPlayMode) -> String {
        switch mode {
        case .closed: return "closed"
        case .open: return "open"
        }
    }

    private func pointToken(_ point: CGPoint) -> String {
        "(\(number(point.x)),\(number(point.y)))"
    }

    private func sizeToken(_ size: CGSize) -> String {
        "(\(number(size.width)),\(number(size.height)))"
    }

    private func number(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }

    private func orientationToken(_ orientation: OpponentSeatView.Orientation) -> String {
        switch orientation {
        case .top: return "top"
        case .left: return "left"
        case .right: return "right"
        }
    }

    private func kindToken(_ kind: TableLayoutModel.SlotKind) -> String {
        switch kind {
        case .topWide: return "topWide"
        case .topNarrow: return "topNarrow"
        case .compactHidden: return "compactHidden"
        }
    }

    // MARK: - Engine fixtures

    private func makeFreshDealEngine() throws -> PreferansEngine {
        var engine = try PreferansEngine(players: players, rules: .sochi, firstDealer: "south")
        _ = try engine.apply(.startDeal(dealer: "south", deck: Deck.standard32))
        return engine
    }

    private func makeAwaitingDiscardEngine() throws -> PreferansEngine {
        var engine = try makeFreshDealEngine()
        try EngineTestDriver.driveAuctionWinning(
            engine: &engine,
            declarer: "north",
            bid: .game(GameContract(6, .suit(.spades)))
        )
        return engine
    }

    private func makeMidTrickEngine() throws -> PreferansEngine {
        var engine = try makeAwaitingDiscardEngine()
        guard case let .awaitingDiscard(exchange) = engine.state else {
            throw EngineTestError("Expected awaitingDiscard fixture; got \(engine.state.description).")
        }
        _ = try engine.apply(.discard(player: "north", cards: exchange.talon))
        try EngineTestDriver.declareContract(
            engine: &engine,
            declarer: "north",
            contract: GameContract(6, .suit(.spades))
        )
        try EngineTestDriver.forceWhist(engine: &engine)
        guard case let .playing(playing) = engine.state else {
            throw EngineTestError("Expected playing state; got \(engine.state.description).")
        }
        let firstCard = try #require(engine.legalCards(for: playing.currentPlayer).min())
        _ = try engine.apply(.playCard(player: playing.currentPlayer, card: firstCard))
        return engine
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
