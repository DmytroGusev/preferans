import Foundation
import PreferansEngine

public typealias HostedOnlineGameCoordinator = RoomOnlineGameCoordinator

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
