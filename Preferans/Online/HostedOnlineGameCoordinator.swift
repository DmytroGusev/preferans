#if canImport(GameKit)
import Foundation
import GameKit
import PreferansEngine

public typealias HostedOnlineGameCoordinator = RoomOnlineGameCoordinator

extension RoomOnlineGameCoordinator {
    public func attach(match: GKMatch, rules: PreferansRules = .sochi) async {
        await attach(transport: GameKitRoomTransport(match: match), rules: rules)
    }
}

public func defaultCloudStore() -> (any GameArchiveStore)? {
    #if canImport(CloudKit)
    guard AppIdentifiers.cloudKitContainer != "iCloud.com.example.preferans" else {
        return nil
    }
    return CloudKitGameArchiveStore()
    #else
    return nil
    #endif
}
#endif
