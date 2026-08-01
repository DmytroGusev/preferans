import Foundation

/// Single-flight state for the online host's durable-before-visible barrier.
///
/// A staged update receives a generation ticket. Retry tasks must present that
/// ticket whenever they read, back off, or complete the update, so a cancelled
/// task from an older host epoch cannot clear a newer pending move.
struct RoomDurabilityBarrier<Update> {
    struct Ticket: Equatable, Sendable {
        fileprivate let generation: UInt64
    }

    private struct Staged {
        var ticket: Ticket
        var update: Update
    }

    private let initialRetryDelay: Duration
    private let maximumRetryDelay: Duration
    private var generation: UInt64 = 0
    private var staged: Staged?
    private var retryDelay: Duration

    init(
        initialRetryDelay: Duration,
        maximumRetryDelay: Duration = .seconds(8)
    ) {
        self.initialRetryDelay = initialRetryDelay
        self.maximumRetryDelay = maximumRetryDelay
        self.retryDelay = initialRetryDelay
    }

    var acceptsAction: Bool {
        staged == nil
    }

    mutating func stage(_ update: Update) -> Ticket? {
        guard staged == nil else { return nil }
        generation &+= 1
        let ticket = Ticket(generation: generation)
        staged = Staged(ticket: ticket, update: update)
        retryDelay = initialRetryDelay
        return ticket
    }

    func update(for ticket: Ticket) -> Update? {
        guard staged?.ticket == ticket else { return nil }
        return staged?.update
    }

    func delay(for ticket: Ticket) -> Duration? {
        guard staged?.ticket == ticket else { return nil }
        return retryDelay
    }

    @discardableResult
    mutating func recordFailure(for ticket: Ticket) -> Bool {
        guard staged?.ticket == ticket else { return false }
        retryDelay = min(retryDelay * 2, maximumRetryDelay)
        return true
    }

    mutating func complete(_ ticket: Ticket) -> Update? {
        guard staged?.ticket == ticket else { return nil }
        let update = staged?.update
        staged = nil
        retryDelay = initialRetryDelay
        return update
    }

    mutating func reset() {
        staged = nil
        retryDelay = initialRetryDelay
    }
}
