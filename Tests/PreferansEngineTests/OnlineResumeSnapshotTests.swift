import XCTest
@testable import PreferansApp
@testable import PreferansEngine

/// Covers the Durable-Object-backed resume mechanic: a host rebuilt from the
/// engine snapshot the previous host pushed lands on the exact same state and
/// keeps validating play from where the table left off.
final class OnlineResumeSnapshotTests: XCTestCase {
    private let players: [PlayerID] = ["north", "east", "south"]

    func testResumeFromSnapshotMatchesStateAndContinuesPlay() async throws {
        let original = try HostGameActor(
            hostPlayerID: "north",
            seats: seats(),
            rules: .sochi,
            firstDealer: "south",
            dealSource: ScriptedDealSource(decks: [Deck.standard32])
        )
        // Advance into bidding so the snapshot captures a mid-deal state.
        _ = try await original.applyClientAction(
            ClientActionEnvelope(
                tableID: original.tableID,
                actor: "north",
                action: .startDeal(dealer: nil, deck: nil),
                baseHostSequence: 0
            ),
            sender: "north"
        )

        let snapshot = await original.engineSnapshot
        let sequence = await original.currentSequence
        let originalSnapshot = await original.currentSnapshot

        // Rebuild a fresh host purely from the durable snapshot (no action log).
        let resumed = try HostGameActor(
            tableID: UUID(),
            hostPlayerID: "north",
            seats: seats(),
            resumeSnapshot: snapshot,
            sequence: sequence,
            dealSource: ScriptedDealSource(decks: [Deck.standard32])
        )

        let resumedSnapshot = await resumed.currentSnapshot
        let resumedSequence = await resumed.currentSequence
        XCTAssertEqual(resumedSnapshot, originalSnapshot, "Resumed engine state must equal the pre-teardown state.")
        XCTAssertEqual(resumedSequence, sequence, "Resumed host must continue the host sequence.")

        // The resumed host validates the next legal action (a pass by whoever is
        // on the clock) and advances the sequence — proving play continues.
        let onClock = try XCTUnwrap(originalSnapshot.state.currentActor)
        let next = try await resumed.applyClientAction(
            ClientActionEnvelope(
                tableID: resumed.tableID,
                actor: onClock,
                action: .bid(player: onClock, call: .pass),
                baseHostSequence: sequence
            ),
            sender: onClock
        )
        XCTAssertEqual(next.sequence, sequence + 1)
    }

    func testFinishedGameReportsFinishedStatus() async throws {
        // A lobby-state host (sequence 0, waiting for deal) reports `.lobby`;
        // once a match ends the status flips to `.finished` (see currentStatus).
        let host = try HostGameActor(
            hostPlayerID: "north",
            seats: seats(),
            rules: .sochi,
            firstDealer: "south",
            dealSource: ScriptedDealSource(decks: [Deck.standard32])
        )
        let initial = await host.initialUpdate()
        XCTAssertEqual(initial.status, .lobby)
        XCTAssertEqual(initial.dealNumber, 1)
    }

    private func seats() -> [PlayerIdentity] {
        players.map {
            PlayerIdentity(playerID: $0, gamePlayerID: $0.rawValue, displayName: $0.rawValue)
        }
    }
}
