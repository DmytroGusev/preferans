import XCTest
@testable import PreferansApp
@testable import PreferansEngine

@MainActor
final class GameViewModelDealSourceTests: XCTestCase {
    /// Anchors the deal so `activePlayers[0]` is `north` and the deck is the
    /// sorted standard deck. With `firstDealer = "south"` and 3 players, the
    /// rotation produces `activePlayers = [north, east, south]`, so the first
    /// bidder is always `north`.
    private func makeModel(dealSource: DealSource) throws -> GameViewModel {
        try GameViewModel(
            players: ["north", "east", "south"],
            rules: .sochi,
            firstDealer: "south",
            viewerPolicy: .followsActor,
            dealSource: dealSource
        )
    }

    func testStartDealConsumesDeckFromDealSource() throws {
        let scripted = ScriptedDealSource(decks: [Deck.standard32])
        let model = try makeModel(dealSource: scripted)

        model.startDeal()

        XCTAssertNil(model.lastError)
        guard case let .bidding(state) = model.engine.state else {
            return XCTFail("Expected bidding state after startDeal.")
        }
        // With deck = sorted(♠7,♠8,♠9,♠10,♠J,♠Q,...) and activePlayers
        // [north, east, south], the first packet hands the lowest-ranked
        // spades out in pairs to each seat. Talon then takes ♠K and ♠A.
        XCTAssertEqual(state.talon, [Card(.spades, .king), Card(.spades, .ace)])
        XCTAssertEqual(state.hands["north"]?.contains(Card(.spades, .seven)), true)
        XCTAssertEqual(state.currentPlayer, "north")
    }

    func testTwoModelsWithSameSeedReachIdenticalBiddingStateAfterDeal() throws {
        let modelA = try makeModel(dealSource: SeededDealSource(seed: 4242))
        let modelB = try makeModel(dealSource: SeededDealSource(seed: 4242))

        modelA.startDeal()
        modelB.startDeal()

        guard case let .bidding(stateA) = modelA.engine.state,
              case let .bidding(stateB) = modelB.engine.state else {
            return XCTFail("Both models should reach bidding.")
        }
        XCTAssertEqual(stateA.hands, stateB.hands)
        XCTAssertEqual(stateA.talon, stateB.talon)
    }

    func testAllPassDealReachesPlayingPhaseDeterministically() throws {
        let model = try makeModel(dealSource: ScriptedDealSource(decks: [Deck.standard32]))
        model.startDeal()

        // viewerPolicy is .followsActor, so selectedViewer always equals
        // the engine's current bidder. Three Pass calls drive an all-pass.
        for _ in 0..<3 {
            model.send(.bid(player: model.selectedViewer, call: .pass))
        }

        XCTAssertNil(model.lastError)
        guard case let .playing(playing) = model.engine.state,
              case .allPass = playing.kind else {
            return XCTFail("Three passes should land the engine in all-pass play.")
        }
    }

}
