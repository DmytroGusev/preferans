import Foundation
import XCTest
import PreferansEngine

final class PublicTableRulesTests: XCTestCase {
    func testWorkerPublicPresetsMatchTheActualSwiftScoringRules() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("workers/room-worker/fixtures/public-rules.json"))
        let profiles = try JSONDecoder().decode([String: PreferansRules].self, from: data)
        XCTAssertEqual(profiles["odesa"], .sochi)
        XCTAssertEqual(profiles["wien"], .leningrad)
        XCTAssertEqual(profiles["thessaloniki"], .rostov)
    }
}
