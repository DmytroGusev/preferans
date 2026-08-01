import Foundation

/// Pure host-contact state for a room client.
///
/// The coordinator owns the task that sends probes; this value owns the
/// transition invariants so timeout and recovery behavior can be exercised
/// without sleeping or opening a transport.
struct RoomHostLiveness {
    private(set) var status: OnlineLiveness = .connecting
    private(set) var lastContact: ContinuousClock.Instant?

    mutating func reset() {
        status = .connecting
        lastContact = nil
    }

    mutating func beginClientSession(at now: ContinuousClock.Instant) {
        status = .connecting
        lastContact = now
    }

    mutating func becomeHost() {
        status = .live
        lastContact = nil
    }

    /// Returns true only for the unreachable-to-live recovery edge, whose
    /// caller must request a full projection resync.
    mutating func noteHostContact(at now: ContinuousClock.Instant) -> Bool {
        let needsResync = status == .hostUnreachable
        status = .live
        lastContact = now
        return needsResync
    }

    /// Marks the host unreachable exactly when its deadline is reached.
    /// Returns whether this call changed the public state.
    mutating func markUnreachableIfTimedOut(
        at now: ContinuousClock.Instant,
        timeout: Duration
    ) -> Bool {
        guard status != .hostUnreachable,
              let lastContact,
              lastContact.duration(to: now) >= timeout else { return false }
        status = .hostUnreachable
        return true
    }
}
