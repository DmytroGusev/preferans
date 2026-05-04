import Foundation

extension PreferansEngine {
    mutating func reduceWhist(player: PlayerID, call: WhistCall) throws -> EngineTransition {
        guard case var .awaitingWhist(whist) = state else {
            throw PreferansError.invalidState(expected: "awaitingWhist", actual: state.description)
        }
        try validateCurrent(player, expected: whist.currentPlayer)
        guard legalWhistCalls(in: whist, for: player).contains(call) else {
            throw PreferansError.illegalWhist("\(call) is not legal for \(player).")
        }

        let record = WhistCallRecord(player: player, call: call)
        whist.calls.append(record)
        var events: [PreferansEvent] = [.whistAccepted(record)]

        let first = whist.defenders[0]
        let second = whist.defenders[1]

        switch whist.flow {
        case .normal:
            if player == first {
                whist.currentPlayer = second
                return EngineTransition(state: .awaitingWhist(whist), events: events)
            }

            let firstCall = whist.calls.first { $0.player == first }?.call
            if firstCall == .pass {
                switch call {
                case .pass:
                    let transition = scorePassedOut(whist)
                    return EngineTransition(state: transition.state, events: events + transition.events)
                case .whist:
                    return EngineTransition(
                        state: .awaitingDefenderMode(makeDefenderModeState(whist: whist, whister: second)),
                        events: events
                    )
                case .halfWhist:
                    whist.currentPlayer = first
                    whist.flow = .firstDefenderSecondChance(halfWhister: second)
                    return EngineTransition(state: .awaitingWhist(whist), events: events)
                }
            }

            switch call {
            case .pass:
                return EngineTransition(
                    state: .awaitingDefenderMode(makeDefenderModeState(whist: whist, whister: first)),
                    events: events
                )
            case .whist:
                let playing = startGamePlay(from: whist, whisters: [first, second], mode: .closed)
                events.append(.playStarted(playing.kind))
                return EngineTransition(state: .playing(playing), events: events)
            case .halfWhist:
                throw PreferansError.illegalWhist("Half-whist is only legal after first defender passes.")
            }

        case let .firstDefenderSecondChance(halfWhister):
            switch call {
            case .pass:
                let transition = scoreHalfWhist(whist, halfWhister: halfWhister)
                return EngineTransition(state: transition.state, events: events + transition.events)
            case .whist:
                let playing = startGamePlay(from: whist, whisters: [first, halfWhister], mode: .closed)
                events.append(.playStarted(playing.kind))
                return EngineTransition(state: .playing(playing), events: events)
            case .halfWhist:
                throw PreferansError.illegalWhist("Half-whist is not legal on second chance.")
            }
        }
    }

    func reduceChooseDefenderMode(player: PlayerID, mode: DefenderPlayMode) throws -> EngineTransition {
        guard case let .awaitingDefenderMode(defenderMode) = state else {
            throw PreferansError.invalidState(expected: "awaitingDefenderMode", actual: state.description)
        }
        try validateCurrent(player, expected: defenderMode.whister)

        let playing = makePlayingState(
            dealer: defenderMode.dealer,
            activePlayers: defenderMode.activePlayers,
            hands: defenderMode.hands,
            talon: defenderMode.talon,
            discard: defenderMode.discard,
            kind: .game(
                GamePlayContext(
                    declarer: defenderMode.declarer,
                    contract: defenderMode.contract,
                    defenders: defenderMode.defenders,
                    whisters: [defenderMode.whister],
                    defenderPlayMode: mode,
                    whistCalls: defenderMode.whistCalls,
                    bonusPoolOnSuccess: defenderMode.bonusPoolOnSuccess
                )
            )
        )
        return EngineTransition(
            state: .playing(playing),
            events: [.defenderModeChosen(whister: player, mode: mode), .playStarted(playing.kind)]
        )
    }
}
