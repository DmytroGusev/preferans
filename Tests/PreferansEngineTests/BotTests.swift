import XCTest
@testable import PreferansEngine

/// Verifies the bot can drive every phase of every contract variant from
/// the dealt-cards state through to a scored result, without ever picking
/// an illegal action.
final class BotTests: XCTestCase {
    private let players: [PlayerID] = ["N", "E", "S"]

    func testStrategyDrivesEntireGameDealToFinish() async throws {
        let strategy = HeuristicStrategy(planner: CardPlayPlanner(samples: 6, rolloutsPerSample: 1))
        let outcome = try await playOneDeal(strategy: strategy, deck: makeDeck(.strongSpades))
        XCTAssertNotNil(outcome.result)
        switch outcome.result?.kind {
        case .game, .halfWhist, .passedOut, .misere:
            break
        default:
            XCTFail("Unexpected deal result: \(String(describing: outcome.result?.kind))")
        }
    }

    func testStrategyDrivesMisereDealToFinish() async throws {
        let strategy = HeuristicStrategy(planner: CardPlayPlanner(samples: 6, rolloutsPerSample: 1))
        let outcome = try await playOneDeal(strategy: strategy, deck: makeDeck(.misereForNorth))
        XCTAssertNotNil(outcome.result)
    }

    func testStrategyDrivesAllPassDealToFinish() async throws {
        let strategy = HeuristicStrategy(planner: CardPlayPlanner(samples: 4, rolloutsPerSample: 1))
        let outcome = try await playOneDeal(strategy: strategy, deck: makeDeck(.allWeak))
        XCTAssertNotNil(outcome.result)
    }

    func testFiveConsecutiveBotDealsAllReachAScoredResult() async throws {
        let strategy = HeuristicStrategy(planner: CardPlayPlanner(samples: 4, rolloutsPerSample: 1))
        var engine = try PreferansEngine(players: players)
        for dealIndex in 0..<5 {
            _ = try engine.startDeal(deck: Deck.standard32.shuffled())
            let drive = try await BotTestDriver.drive(engine: &engine, strategy: strategy)
            XCTAssertFalse(drive.stalled, "Bot strategy stalled on deal \(dealIndex) after \(drive.steps) steps.")
            switch engine.state {
            case .dealFinished, .gameOver:
                break
            default:
                return XCTFail("Deal \(dealIndex) did not reach a finished state: \(engine.state.description)")
            }
            if case .gameOver = engine.state { break }
        }
    }

    // MARK: - Driver

    private struct DealOutcome {
        var result: DealResult?
        var stepCount: Int
    }

    private func playOneDeal(strategy: PlayerStrategy, deck: [Card]) async throws -> DealOutcome {
        // First dealer = "S" so the active rotation is [N, E, S] — what
        // makeDeck assumes when laying out cards.
        var engine = try PreferansEngine(players: players, firstDealer: "S")
        _ = try engine.startDeal(deck: deck)
        let drive = try await BotTestDriver.drive(engine: &engine, strategy: strategy)
        if drive.stalled {
            XCTFail("Strategy stalled in \(engine.state.description) after \(drive.steps) steps.")
        }
        var result: DealResult? = nil
        switch engine.state {
        case let .dealFinished(r): result = r
        case let .gameOver(s): result = s.lastDeal
        default: break
        }
        return DealOutcome(result: result, stepCount: drive.steps)
    }

    // MARK: - Deck stacking helpers

    private enum DealerPattern {
        case strongSpades, misereForNorth, allWeak
    }

    private func cards(_ suit: Suit, _ ranks: [Rank]) -> [Card] {
        ranks.map { Card(suit, $0) }
    }

    private func makeDeck(_ pattern: DealerPattern) -> [Card] {
        switch pattern {
        case .strongSpades:
            return assemble(
                north: cards(.spades, Rank.allCases) + cards(.clubs, [.ace]) + cards(.hearts, [.ace]),
                east: cards(.clubs, [.king, .queen, .jack, .ten, .nine, .eight, .seven])
                    + cards(.hearts, [.queen, .jack, .ten]),
                south: cards(.diamonds, Rank.allCases) + cards(.hearts, [.nine, .eight]),
                talon: cards(.hearts, [.seven, .king])
            )
        case .misereForNorth:
            return assemble(
                north: cards(.spades, [.seven, .eight, .nine])
                    + cards(.clubs, [.seven, .eight])
                    + cards(.diamonds, [.seven, .eight])
                    + cards(.hearts, [.seven, .eight, .nine]),
                east: cards(.spades, [.ten, .jack, .queen]) + cards(.clubs, [.nine, .ten, .jack, .queen])
                    + cards(.diamonds, [.nine, .ten, .jack]),
                south: cards(.spades, [.king, .ace]) + cards(.clubs, [.king, .ace])
                    + cards(.diamonds, [.queen, .king, .ace]) + cards(.hearts, [.ten, .jack, .queen]),
                talon: cards(.hearts, [.king, .ace])
            )
        case .allWeak:
            return assemble(
                north: cards(.spades, [.seven, .eight, .nine, .ten])
                    + cards(.clubs, [.seven, .eight, .nine])
                    + cards(.diamonds, [.seven, .eight, .nine]),
                east: cards(.spades, [.jack]) + cards(.clubs, [.ten, .jack, .queen, .king])
                    + cards(.diamonds, [.ten, .jack, .queen, .king, .ace]),
                south: cards(.spades, [.queen, .king, .ace])
                    + cards(.clubs, [.ace])
                    + cards(.hearts, [.seven, .eight, .nine, .ten, .jack, .queen]),
                talon: cards(.hearts, [.king, .ace])
            )
        }
    }

    /// Engine deals in 5 packets of 2 cards per active seat with the talon
    /// landing in packet 0. Reverse-engineering the deck order from desired
    /// hands lets a test cover a specific scenario without scanning random
    /// shuffles.
    private func assemble(north: [Card], east: [Card], south: [Card], talon: [Card]) -> [Card] {
        DealDeckLayout.deck(
            hands: ["N": north, "E": east, "S": south],
            talon: talon,
            activePlayers: players
        )
    }
}
