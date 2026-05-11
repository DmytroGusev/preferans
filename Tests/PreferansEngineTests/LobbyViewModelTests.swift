import XCTest
@testable import PreferansApp
import PreferansEngine

@MainActor
final class LobbyViewModelTests: AppTestCase {
    func testBotStepperAddsAndRemovesFourthBot() {
        let model = LobbyViewModel()

        XCTAssertEqual(model.seats.count, 3)
        XCTAssertEqual(model.botCount, 2)
        XCTAssertTrue(model.canAddBot)
        XCTAssertFalse(model.canRemoveBot)

        model.addBot()

        XCTAssertEqual(model.seats.count, 4)
        XCTAssertEqual(model.botCount, 3)
        XCTAssertEqual(model.seats.last?.name, "Agent Smith")
        XCTAssertFalse(model.canAddBot)
        XCTAssertTrue(model.canRemoveBot)

        model.removeBot()

        XCTAssertEqual(model.seats.count, 3)
        XCTAssertEqual(model.botCount, 2)
        XCTAssertTrue(model.canAddBot)
        XCTAssertFalse(model.canRemoveBot)
    }

    func testStartLocalTableAssignsBotStrategiesFromRoster() throws {
        let model = LobbyViewModel()

        model.startLocalTable()

        let game = try XCTUnwrap(model.localModel)
        XCTAssertNil(model.errorText)
        XCTAssertNotNil(game.botStrategies["Morpheus"])
        XCTAssertNotNil(game.botStrategies["Trinity"])
        XCTAssertNil(game.botStrategies["Neo"])
    }
}
