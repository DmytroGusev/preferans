import Foundation

/// Owns the wire-level dispatch table for one room attachment.
///
/// The coordinator remains responsible for authority checks and state changes;
/// this collaborator only turns a received message into the corresponding
/// typed effect. Keeping that mapping in one place prevents a new wire message
/// from growing the coordinator's state machine or accidentally bypassing the
/// existing validation path.
@MainActor
final class RoomInboundMessageDispatcher {
    typealias SeatAssignmentHandler = @MainActor (SeatAssignmentEnvelope, ReceivedRoomMessage) async -> Void
    typealias HelloHandler = @MainActor (HelloEnvelope, ReceivedRoomMessage) async -> Void
    typealias ClientActionHandler = @MainActor (ClientActionEnvelope, ReceivedRoomMessage) async -> Void
    typealias ProjectionHandler = @MainActor (ProjectionEnvelope, ReceivedRoomMessage) async -> Void
    typealias HostErrorHandler = @MainActor (HostErrorEnvelope, ReceivedRoomMessage) async -> Void
    typealias ResyncRequestHandler = @MainActor (ResyncRequestEnvelope, ReceivedRoomMessage) async -> Void
    typealias PingHandler = @MainActor (PingEnvelope, ReceivedRoomMessage) async -> Void

    var seatAssignment: SeatAssignmentHandler?
    var hello: HelloHandler?
    var clientAction: ClientActionHandler?
    var projection: ProjectionHandler?
    var hostError: HostErrorHandler?
    var resyncRequest: ResyncRequestHandler?
    var ping: PingHandler?

    func dispatch(_ received: ReceivedRoomMessage) async {
        switch received.message {
        case let .seatAssignment(assignment):
            await invoke(seatAssignment, payload: assignment, received: received, name: "seatAssignment")
        case let .hello(hello):
            await invoke(self.hello, payload: hello, received: received, name: "hello")
        case let .clientAction(envelope):
            await invoke(clientAction, payload: envelope, received: received, name: "clientAction")
        case let .projection(envelope):
            await invoke(projection, payload: envelope, received: received, name: "projection")
        case let .hostError(error):
            await invoke(hostError, payload: error, received: received, name: "hostError")
        case let .resyncRequest(request):
            await invoke(resyncRequest, payload: request, received: received, name: "resyncRequest")
        case let .ping(ping):
            await invoke(self.ping, payload: ping, received: received, name: "ping")
        }
    }

    private func invoke<Payload>(
        _ handler: (@MainActor (Payload, ReceivedRoomMessage) async -> Void)?,
        payload: Payload,
        received: ReceivedRoomMessage,
        name: StaticString
    ) async {
        guard let handler else {
            preconditionFailure("Inbound message handler is not configured: \(name)")
        }
        await handler(payload, received)
    }
}
