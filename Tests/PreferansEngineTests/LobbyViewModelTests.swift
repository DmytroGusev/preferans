import XCTest
@testable import PreferansApp
import PreferansEngine

@MainActor
final class LobbyViewModelTests: XCTestCase {
    func testSeatResizeClampsSelectedOnlineSeat() {
        let model = LobbyViewModel()

        model.setSeatCount(4)
        model.onlineSeatIndex = 3
        model.setSeatCount(3)

        XCTAssertEqual(model.onlineSeatIndex, 2)
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
