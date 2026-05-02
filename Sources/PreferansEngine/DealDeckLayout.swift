import Foundation

/// Canonical Preferans deal layout.
///
/// The engine deals five packets of two cards to each active seat, inserting
/// the two-card talon after the first packet. Test fixtures and scripted
/// decks use the inverse operation here so their desired per-seat hands stay
/// tied to the same packet layout the engine consumes.
public enum DealDeckLayout {
    public static let handSize = 10
    public static let talonSize = 2
    private static let packetCount = 5
    private static let cardsPerPacketPerSeat = 2

    public struct Deal: Equatable, Sendable {
        public var hands: [PlayerID: [Card]]
        public var talon: [Card]

        public init(hands: [PlayerID: [Card]], talon: [Card]) {
            self.hands = hands
            self.talon = talon
        }
    }

    public static func deal(deck originalDeck: [Card], activePlayers: [PlayerID]) -> Deal {
        var deck = originalDeck
        var hands = activePlayers.dictionary(filledWith: [Card]())
        var talon: [Card] = []

        for packet in 0..<packetCount {
            for player in activePlayers {
                hands[player, default: []].append(deck.removeFirst())
                hands[player, default: []].append(deck.removeFirst())
            }
            if packet == 0 {
                talon.append(deck.removeFirst())
                talon.append(deck.removeFirst())
            }
        }

        for player in activePlayers {
            hands[player]?.sort()
        }
        return Deal(hands: hands, talon: talon)
    }

    public static func deck(hands: [PlayerID: [Card]], talon: [Card], activePlayers: [PlayerID]) -> [Card] {
        precondition(activePlayers.count == 3, "DealDeckLayout requires exactly three active seats.")
        precondition(Set(activePlayers).count == activePlayers.count, "Active players must be unique.")
        precondition(talon.count == talonSize, "Talon must contain exactly two cards.")

        var deck: [Card] = []
        deck.reserveCapacity(Deck.standard32.count)
        for packet in 0..<packetCount {
            for seat in activePlayers {
                guard let hand = hands[seat] else {
                    preconditionFailure("Deck layout missing hand for seat \(seat).")
                }
                precondition(hand.count == handSize, "Seat \(seat) must have exactly \(handSize) cards.")
                let offset = packet * cardsPerPacketPerSeat
                deck.append(hand[offset])
                deck.append(hand[offset + 1])
            }
            if packet == 0 {
                deck.append(contentsOf: talon)
            }
        }
        precondition(Set(deck) == Set(Deck.standard32), "Deck layout must produce a standard 32-card permutation.")
        return deck
    }

    public static func deck(north: [Card], east: [Card], south: [Card], talon: [Card]) -> [Card] {
        deck(
            hands: [
                "north": north,
                "east": east,
                "south": south
            ],
            talon: talon,
            activePlayers: ["north", "east", "south"]
        )
    }
}
