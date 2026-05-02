import XCTest
@testable import PreferansEngine

final class DealSourceTests: XCTestCase {
    func testSeededRandomNumberGeneratorIsDeterministicForSameSeed() {
        let a = SeededRandomNumberGenerator(seed: 42)
        let b = SeededRandomNumberGenerator(seed: 42)
        for _ in 0..<32 {
            XCTAssertEqual(a.next(), b.next())
        }
    }

    func testSeededRandomNumberGeneratorDivergesForDifferentSeeds() {
        let a = SeededRandomNumberGenerator(seed: 42)
        let b = SeededRandomNumberGenerator(seed: 43)
        let aRolls = (0..<8).map { _ in a.next() }
        let bRolls = (0..<8).map { _ in b.next() }
        XCTAssertNotEqual(aRolls, bRolls)
    }

    func testDeckShuffledWithSeedIsReproducible() {
        let first = Deck.shuffled(seed: 7)
        let second = Deck.shuffled(seed: 7)
        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(first), Set(Deck.standard32))
        XCTAssertNotEqual(first, Deck.standard32, "a healthy shuffle should not match the sorted deck")
    }

    func testSeededDealSourceProducesIdenticalSequenceForSameSeed() {
        let a = SeededDealSource(seed: 99)
        let b = SeededDealSource(seed: 99)
        for _ in 0..<5 {
            XCTAssertEqual(a.nextDeck(), b.nextDeck())
        }
    }

    func testSeededDealSourceAdvancesPerCall() {
        let source = SeededDealSource(seed: 99)
        let first = source.nextDeck()
        let second = source.nextDeck()
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(Set(first), Set(second), "every deal must be a permutation of the same 32 cards")
    }

    func testScriptedDealSourceCyclesThroughGivenDecks() {
        let deckA = Deck.standard32
        let deckB = Array(Deck.standard32.reversed())
        let source = ScriptedDealSource(decks: [deckA, deckB])
        XCTAssertEqual(source.nextDeck(), deckA)
        XCTAssertEqual(source.nextDeck(), deckB)
        XCTAssertEqual(source.nextDeck(), deckA, "scripted source should wrap around once exhausted")
    }

    func testSeededDealSourceFeedsTheEngineDeterministically() throws {
        var engineA = try PreferansEngine(players: ["north", "east", "south"], firstDealer: "north")
        var engineB = try PreferansEngine(players: ["north", "east", "south"], firstDealer: "north")
        let sourceA = SeededDealSource(seed: 12345)
        let sourceB = SeededDealSource(seed: 12345)

        try engineA.startDeal(deck: sourceA.nextDeck())
        try engineB.startDeal(deck: sourceB.nextDeck())

        guard case let .bidding(stateA) = engineA.state,
              case let .bidding(stateB) = engineB.state else {
            return XCTFail("Both engines should be in bidding state.")
        }
        XCTAssertEqual(stateA.hands, stateB.hands)
        XCTAssertEqual(stateA.talon, stateB.talon)
    }
}
