import XCTest
@testable import PreferansApp
import PreferansEngine

final class SeatRoleBadgeFeedTests: XCTestCase {
    private let players: [PlayerID] = ["north", "east", "south"]

    func testBiddingHasNoPersistentRoleBadges() {
        let projection = makeProjection(
            phase: .bidding(currentPlayer: "north", highestBid: nil),
            seats: [
                seat("north", role: .active),
                seat("east", role: .active),
                seat("south", role: .active),
            ]
        )

        XCTAssertTrue(SeatRoleBadgeFeed.perSeat(from: projection).isEmpty)
    }

    func testPlayingDerivesSameRoleMapForEveryLayout() {
        let contract = GameContract(6, .suit(.spades))
        let projection = makeProjection(
            phase: .playing(
                currentPlayer: "north",
                leader: "north",
                kind: .game(
                    declarer: "north",
                    contract: contract,
                    defenders: ["east", "south"],
                    whisters: ["east"],
                    defenderPlayMode: .closed
                )
            ),
            seats: [
                seat("north", role: .declarer),
                seat("east", role: .whister),
                seat("south", role: .defender),
            ],
            whistCalls: [
                WhistCallRecord(player: "east", call: .whist),
                WhistCallRecord(player: "south", call: .pass),
            ]
        )

        XCTAssertEqual(
            SeatRoleBadgeFeed.perSeat(from: projection),
            [
                "north": .declarer,
                "east": .whist,
                "south": .pass,
            ]
        )
    }

    private func seat(_ player: PlayerID, role: SeatRole) -> SeatProjection {
        SeatProjection(
            player: player,
            displayName: player.rawValue,
            isActive: true,
            isDealer: false,
            isCurrentActor: false,
            role: role,
            hand: [],
            trickCount: 0
        )
    }

    private func makeProjection(
        phase: ProjectedPhase,
        seats: [SeatProjection],
        whistCalls: [WhistCallRecord] = []
    ) -> PlayerGameProjection {
        PlayerGameProjection(
            tableID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            sequence: 1,
            viewer: "north",
            players: players,
            identities: [],
            rules: .sochi,
            match: MatchSettings(raspasy: .sochi),
            consecutiveAllPassDeals: 0,
            score: ScoreSheet(players: players),
            phase: phase,
            seats: seats,
            auction: [],
            whistCalls: whistCalls,
            currentTrick: [],
            lastCompletedTrick: nil,
            completedTrickCount: 0,
            trickCounts: players.dictionary(filledWith: 0),
            talon: [],
            discard: [],
            legal: LegalActionProjection(),
            status: .readyToDeal
        )
    }
}
