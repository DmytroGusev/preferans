import Foundation

struct EngineTransition: Sendable {
    var state: DealState
    var events: [PreferansEvent]
}
