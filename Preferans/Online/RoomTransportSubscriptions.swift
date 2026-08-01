import Foundation

/// Owns the three long-lived streams associated with one room transport.
///
/// The coordinator still interprets messages, presence, and connection events;
/// this type owns only task replacement and cancellation. Keeping the streams
/// together gives attachment teardown one boundary instead of three task slots
/// that can drift apart as the coordinator evolves.
@MainActor
final class RoomTransportSubscriptions {
    typealias MessageHandler = @MainActor @Sendable (ReceivedRoomMessage) async -> Void
    typealias ParticipantsHandler = @MainActor @Sendable ([OnlinePeer]) async -> Void
    typealias ConnectionHandler = @MainActor @Sendable (RoomTransportEvent) async -> Void

    private var messagesTask: Task<Void, Never>?
    private var participantsTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?

    deinit {
        messagesTask?.cancel()
        participantsTask?.cancel()
        connectionTask?.cancel()
    }

    func observeMessages(
        _ stream: AsyncStream<ReceivedRoomMessage>,
        handler: @escaping MessageHandler
    ) {
        messagesTask?.cancel()
        messagesTask = Task { @MainActor in
            for await message in stream {
                guard !Task.isCancelled else { return }
                await handler(message)
            }
        }
    }

    func observeParticipants(
        _ stream: AsyncStream<[OnlinePeer]>,
        handler: @escaping ParticipantsHandler
    ) {
        participantsTask?.cancel()
        participantsTask = Task { @MainActor in
            for await participants in stream {
                guard !Task.isCancelled else { return }
                await handler(participants)
            }
        }
    }

    func observeConnectionEvents(
        _ stream: AsyncStream<RoomTransportEvent>,
        handler: @escaping ConnectionHandler
    ) {
        connectionTask?.cancel()
        connectionTask = Task { @MainActor in
            for await event in stream {
                guard !Task.isCancelled else { return }
                await handler(event)
            }
        }
    }

    func cancelAll() {
        messagesTask?.cancel()
        messagesTask = nil
        participantsTask?.cancel()
        participantsTask = nil
        connectionTask?.cancel()
        connectionTask = nil
    }
}
