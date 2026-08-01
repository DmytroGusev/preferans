import Foundation

/// Deterministic exponential backoff shared by online recovery paths.
///
/// Keeping the schedule in a value type makes its bounds testable and prevents
/// each asynchronous loop from quietly inventing a different retry policy.
struct RoomRetryBackoff: Sendable {
    private static let minimumDelay: Duration = .nanoseconds(1)

    let initialDelay: Duration
    let maximumDelay: Duration
    private(set) var currentDelay: Duration

    init(initialDelay: Duration, maximumDelay: Duration) {
        let boundedInitial = max(initialDelay, Self.minimumDelay)
        self.initialDelay = boundedInitial
        self.maximumDelay = max(maximumDelay, boundedInitial)
        self.currentDelay = boundedInitial
    }

    mutating func recordFailure() {
        currentDelay = min(currentDelay * 2, maximumDelay)
    }

    mutating func reset() {
        currentDelay = initialDelay
    }
}
