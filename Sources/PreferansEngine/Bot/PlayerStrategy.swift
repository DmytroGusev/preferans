import Foundation

/// A pluggable decision-maker for a single seat. The view model invokes the
/// strategy whenever the active actor is a bot seat and applies the returned
/// action through the engine. Strategies must be pure functions of the
/// snapshot — the same input may be replayed during testing.
public protocol PlayerStrategy: Sendable {
    /// Decides the next action for `viewer`. Returns `nil` only when the
    /// strategy refuses to act (e.g., the snapshot is not actually awaiting
    /// `viewer`); in normal use this never returns `nil` for a seat the
    /// caller has confirmed is the active actor.
    func decide(
        snapshot: PreferansSnapshot,
        viewer: PlayerID
    ) async -> PreferansAction?
}
