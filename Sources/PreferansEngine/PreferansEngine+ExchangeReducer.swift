import Foundation

extension PreferansEngine {
    func reduceDiscard(player: PlayerID, cards: [Card]) throws -> EngineTransition {
        guard case var .awaitingDiscard(exchange) = state else {
            throw PreferansError.invalidState(expected: "awaitingDiscard", actual: state.description)
        }
        try validateCurrent(player, expected: exchange.declarer)
        guard cards.count == 2 else {
            throw PreferansError.illegalCardPlay("Discard must contain exactly two cards.")
        }
        guard Set(cards).count == cards.count else {
            throw PreferansError.duplicateCards(cards)
        }

        let originalHand = exchange.hands[player] ?? []
        var combined = originalHand + exchange.talon
        for card in cards {
            guard let index = combined.firstIndex(of: card) else {
                throw PreferansError.cardNotInHand(player: player, card: card)
            }
            combined.remove(at: index)
        }
        guard combined.count == 10 else {
            throw PreferansError.illegalCardPlay("Declarer must keep ten cards after discard.")
        }
        exchange.hands[player] = combined.sorted()

        let exchangeEvent = PreferansEvent.talonExchanged(
            declarer: player,
            talon: exchange.talon,
            discard: cards
        )

        switch exchange.finalBid {
        case .misere:
            let playing = makePlayingState(
                dealer: exchange.dealer,
                activePlayers: exchange.activePlayers,
                hands: exchange.hands,
                talon: exchange.talon,
                discard: cards,
                kind: .misere(MiserePlayContext(declarer: player))
            )
            return EngineTransition(state: .playing(playing), events: [exchangeEvent, .playStarted(playing.kind)])
        case .game, .totus:
            // Totus uses the same contract-declaration step but the legal
            // contract list is constrained to 10-trick options; see
            // ``legalContractDeclarations(for:)``.
            let declaration = ContractDeclarationState(
                dealer: exchange.dealer,
                activePlayers: exchange.activePlayers,
                hands: exchange.hands,
                talon: exchange.talon,
                discard: cards,
                declarer: player,
                finalBid: exchange.finalBid,
                auction: exchange.auction
            )
            return EngineTransition(state: .awaitingContract(declaration), events: [exchangeEvent])
        }
    }

    func reduceDeclareContract(player: PlayerID, contract: GameContract) throws -> EngineTransition {
        guard case let .awaitingContract(declaration) = state else {
            throw PreferansError.invalidState(expected: "awaitingContract", actual: state.description)
        }
        try validateCurrent(player, expected: declaration.declarer)
        let bonusPool: Int
        switch declaration.finalBid {
        case let .game(finalGameBid):
            guard contract >= finalGameBid else {
                throw PreferansError.invalidContract("Declared contract cannot be below the auction bid.")
            }
            bonusPool = 0
        case .totus:
            guard contract.tricks == 10 else {
                throw PreferansError.invalidContract("Totus declaration must be a 10-trick contract.")
            }
            bonusPool = match.totus.bonusPool
        case .misere:
            throw PreferansError.invalidContract("Misere does not enter contract declaration.")
        }

        let defenders = defenders(after: player, activePlayers: declaration.activePlayers)
        if contract.tricks == 10 {
            let playing = makePlayingState(
                dealer: declaration.dealer,
                activePlayers: declaration.activePlayers,
                hands: declaration.hands,
                talon: declaration.talon,
                discard: declaration.discard,
                kind: .game(
                    GamePlayContext(
                        declarer: player,
                        contract: contract,
                        defenders: defenders,
                        whisters: [],
                        defenderPlayMode: .closed,
                        whistCalls: [],
                        bonusPoolOnSuccess: bonusPool
                    )
                )
            )
            return EngineTransition(
                state: .playing(playing),
                events: [
                    .contractDeclared(declarer: player, contract: contract),
                    .playStarted(playing.kind),
                ]
            )
        }

        let whist = WhistState(
            dealer: declaration.dealer,
            activePlayers: declaration.activePlayers,
            hands: declaration.hands,
            talon: declaration.talon,
            discard: declaration.discard,
            declarer: player,
            contract: contract,
            defenders: defenders,
            currentPlayer: defenders[0],
            bonusPoolOnSuccess: bonusPool
        )
        return EngineTransition(
            state: .awaitingWhist(whist),
            events: [.contractDeclared(declarer: player, contract: contract)]
        )
    }
}
