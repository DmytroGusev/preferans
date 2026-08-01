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

    private var generation: UInt64 = 0
    private var staged: Staged?
    private var retryBackoff: RoomRetryBackoff

    init(
        initialRetryDelay: Duration,
        maximumRetryDelay: Duration = .seconds(8)
    ) {
        self.retryBackoff = RoomRetryBackoff(
            initialDelay: initialRetryDelay,
            maximumDelay: maximumRetryDelay
        )
    }

    var acceptsAction: Bool {
        staged == nil
    }

    mutating func stage(_ update: Update) -> Ticket? {
        guard staged == nil else { return nil }
        generation &+= 1
        let ticket = Ticket(generation: generation)
        staged = Staged(ticket: ticket, update: update)
        retryBackoff.reset()
        return ticket
    }

    func update(for ticket: Ticket) -> Update? {
        guard staged?.ticket == ticket else { return nil }
        return staged?.update
    }

    func delay(for ticket: Ticket) -> Duration? {
        guard staged?.ticket == ticket else { return nil }
        return retryBackoff.currentDelay
    }

    @discardableResult
    mutating func recordFailure(for ticket: Ticket) -> Bool {
        guard staged?.ticket == ticket else { return false }
        retryBackoff.recordFailure()
        return true
    }

    mutating func complete(_ ticket: Ticket) -> Update? {
        guard staged?.ticket == ticket else { return nil }
        let update = staged?.update
        staged = nil
        retryBackoff.reset()
        return update
    }

    mutating func reset() {
        staged = nil
        retryBackoff.reset()
    }
}
