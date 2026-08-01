import Foundation
import PreferansEngine

/// One host-driven bot command after pacing and stale-state validation. The
/// coordinator remains responsible for authority and durability; this value
/// only carries the already-decided command and its public-safe explanation.
struct RoomBotMove: Equatable, Sendable {
    var envelope: ClientActionEnvelope
    var sender: PlayerID
    var insight: BotDecisionExplanation?
}

/// Owns the single pending online-bot decision. Scheduling a new state cancels
/// and invalidates the prior task, including strategies that do not immediately
/// cooperate with cancellation. A move is emitted only while the host actor is
/// still awaiting the exact state used to compute it.
@MainActor
final class RoomBotMoveScheduler {
    private let strategy: any PlayerStrategy
    private let delay: Duration
    private var pendingTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var activeTickets: Set<UInt64> = []

    init(
        strategy: any PlayerStrategy = HeuristicStrategy(),
        delay: Duration
    ) {
        self.strategy = strategy
        self.delay = delay
    }

    deinit {
        pendingTask?.cancel()
    }

    var isScheduled: Bool { pendingTask != nil }
    /// Includes invalidated work whose strategy has not returned yet. Kept
    /// internal so deterministic tests can prove non-cooperative cancellation.
    var hasActiveWork: Bool { !activeTickets.isEmpty }

    func cancel() {
        generation &+= 1
        pendingTask?.cancel()
        pendingTask = nil
    }

    func schedule(
        hostActor: HostGameActor,
        tableID: UUID,
        botSeats: Set<PlayerID>,
        onMove: @escaping @MainActor (RoomBotMove) async -> Void
    ) {
        cancel()
        let ticket = generation
        let delay = self.delay
        let strategy = self.strategy
        activeTickets.insert(ticket)

        pendingTask = Task { @MainActor [weak self] in
            defer {
                if let self {
                    self.activeTickets.remove(ticket)
                    if self.generation == ticket {
                        self.pendingTask = nil
                    }
                }
            }
            guard let plan = await hostActor.nextBotDecisionPlan(botSeats: botSeats) else { return }
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard let self,
                  self.generation == ticket,
                  !Task.isCancelled,
                  let decision = await strategy.decision(
                      snapshot: plan.snapshot,
                      viewer: plan.decider
                  ),
                  self.generation == ticket,
                  !Task.isCancelled else { return }

            // A human command or prior bot move may have advanced the actor
            // while pacing/deciding. Never emit that stale command.
            guard await hostActor.stillAwaiting(plan.snapshot),
                  self.generation == ticket,
                  !Task.isCancelled else { return }

            await onMove(RoomBotMove(
                envelope: ClientActionEnvelope(
                    tableID: tableID,
                    actor: decision.action.actor ?? plan.decider,
                    action: decision.action,
                    baseHostSequence: plan.baseSequence
                ),
                sender: plan.decider,
                insight: decision.explanation
            ))
        }
    }
}
