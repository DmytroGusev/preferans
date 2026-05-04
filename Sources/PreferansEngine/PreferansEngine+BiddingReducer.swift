import Foundation

extension PreferansEngine {
    func reduceBid(player: PlayerID, call: BidCall) throws -> EngineTransition {
        guard case var .bidding(bidding) = state else {
            throw PreferansError.invalidState(expected: "bidding", actual: state.description)
        }
        try validateCurrent(player, expected: bidding.currentPlayer)
        guard bidding.activePlayers.contains(player), !bidding.passed.contains(player) else {
            throw PreferansError.illegalBid("Player is not active in the auction.")
        }

        let record = AuctionCall(player: player, call: call)
        var events: [PreferansEvent] = [.bidAccepted(record)]
        bidding.calls.append(record)

        switch call {
        case .pass:
            bidding.passed.insert(player)
        case let .bid(bid):
            guard isLegalBid(bid, by: player, in: bidding) else {
                throw PreferansError.illegalBid("\(bid) is not legal for \(player).")
            }
            bidding.highestBid = bid
            bidding.highestBidder = player
            bidding.significantBidByPlayer[player] = bid
        }

        if bidding.highestBid == nil && bidding.passed.count == bidding.activePlayers.count {
            let playing = makePlayingState(
                dealer: bidding.dealer,
                activePlayers: bidding.activePlayers,
                hands: bidding.hands,
                talon: bidding.talon,
                discard: [],
                kind: .allPass(AllPassPlayContext(talonPolicy: rules.allPassTalonPolicy))
            )
            events.append(.allPassed)
            events.append(.playStarted(playing.kind))
            return EngineTransition(state: .playing(playing), events: events)
        }

        let remaining = bidding.activePlayers.filter { !bidding.passed.contains($0) }
        if let highestBid = bidding.highestBid,
           let declarer = bidding.highestBidder,
           remaining.count == 1 {
            let exchange = ExchangeState(
                dealer: bidding.dealer,
                activePlayers: bidding.activePlayers,
                hands: bidding.hands,
                talon: bidding.talon,
                declarer: declarer,
                finalBid: highestBid,
                auction: bidding.calls
            )
            events.append(.auctionWon(declarer: declarer, bid: highestBid))
            return EngineTransition(state: .awaitingDiscard(exchange), events: events)
        }

        guard let next = nextBidder(after: player, in: bidding) else {
            throw PreferansError.illegalBid("No next bidder is available.")
        }
        bidding.currentPlayer = next
        return EngineTransition(state: .bidding(bidding), events: events)
    }
}
