#if canImport(GameKit) && canImport(UIKit)
import SwiftUI
import UIKit
import GameKit

public struct GameCenterMatchmakerView: UIViewControllerRepresentable {
    public var invite: GKInvite?
    public var minPlayers: Int
    public var maxPlayers: Int
    public var onMatch: (GKMatch) -> Void
    public var onCancel: () -> Void
    public var onError: (Error) -> Void

    public init(
        invite: GKInvite? = nil,
        minPlayers: Int = 3,
        maxPlayers: Int = 4,
        onMatch: @escaping (GKMatch) -> Void,
        onCancel: @escaping () -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.invite = invite
        self.minPlayers = minPlayers
        self.maxPlayers = maxPlayers
        self.onMatch = onMatch
        self.onCancel = onCancel
        self.onError = onError
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(onMatch: onMatch, onCancel: onCancel, onError: onError)
    }

    public func makeUIViewController(context: Context) -> GKMatchmakerViewController {
        let controller: GKMatchmakerViewController
        if let invite {
            controller = GKMatchmakerViewController(invite: invite)!
        } else {
            let request = GKMatchRequest()
            request.minPlayers = minPlayers
            request.maxPlayers = maxPlayers
            request.defaultNumberOfPlayers = minPlayers
            controller = GKMatchmakerViewController(matchRequest: request)!
        }
        controller.matchmakerDelegate = context.coordinator
        return controller
    }

    public func updateUIViewController(_ uiViewController: GKMatchmakerViewController, context: Context) {}

    public final class Coordinator: NSObject, GKMatchmakerViewControllerDelegate {
        private let onMatch: (GKMatch) -> Void
        private let onCancel: () -> Void
        private let onError: (Error) -> Void

        init(onMatch: @escaping (GKMatch) -> Void, onCancel: @escaping () -> Void, onError: @escaping (Error) -> Void) {
            self.onMatch = onMatch
            self.onCancel = onCancel
            self.onError = onError
        }

        public func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
            onCancel()
        }

        public func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
            onError(error)
        }

        public func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
            onMatch(match)
        }
    }
}
#endif
