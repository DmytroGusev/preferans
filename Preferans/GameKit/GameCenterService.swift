#if canImport(GameKit) && canImport(UIKit)
import SwiftUI
import UIKit
import GameKit
import PreferansEngine

@MainActor
public final class GameCenterService: NSObject, ObservableObject, @preconcurrency GKLocalPlayerListener {
    @Published public private(set) var isAuthenticated = GKLocalPlayer.local.isAuthenticated
    @Published public private(set) var statusText = GKLocalPlayer.local.isAuthenticated ? "Game Center ready" : "Game Center signed out"
    @Published public var authenticationViewController: UIViewController?
    @Published public var activeInvite: GKInvite?

    public override init() {
        super.init()
    }

    public var localIdentity: PlayerIdentity? {
        guard GKLocalPlayer.local.isAuthenticated else { return nil }
        let local = GKLocalPlayer.local
        return PlayerIdentity(
            playerID: PlayerID(local.gamePlayerID),
            gamePlayerID: local.gamePlayerID,
            displayName: local.displayName
        )
    }

    public func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                guard let self else { return }
                if let viewController {
                    self.authenticationViewController = viewController
                    self.statusText = "Game Center sign-in required"
                    return
                }
                if let error {
                    self.statusText = "Game Center error: \(error.localizedDescription)"
                    self.isAuthenticated = false
                    return
                }
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                self.statusText = self.isAuthenticated ? "Signed in as \(GKLocalPlayer.local.displayName)" : "Game Center unavailable"
                if self.isAuthenticated {
                    GKLocalPlayer.local.register(self)
                }
            }
        }
    }

    public func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        activeInvite = invite
    }
}

public struct GameCenterAuthenticationPresenter: UIViewControllerRepresentable {
    public var viewController: UIViewController?

    public init(viewController: UIViewController?) {
        self.viewController = viewController
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    public func updateUIViewController(_ presenter: UIViewController, context: Context) {
        guard let viewController, presenter.presentedViewController == nil else { return }
        presenter.present(viewController, animated: true)
    }
}
#endif
