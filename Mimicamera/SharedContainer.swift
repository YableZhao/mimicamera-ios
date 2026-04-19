import Foundation

/// Bridge between the Share Extension and the main app. The extension
/// writes a JPEG into a shared App Group container and opens the main app
/// via a URL scheme; the main app reads the file on launch and kicks off
/// the curate → fit flow.
enum SharedContainer {
    static let appGroupID = "group.com.yablezhao.mimicamera"
    static let pendingReferenceFilename = "pending-reference.jpg"

    /// Fired by the main app after a successful .onOpenURL so ContentView can pick
    /// up the pending reference and run it through curateAndFit.
    static let sharedImageReadyNotification = Notification.Name("MimicameraSharedImageReady")

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var pendingReferenceURL: URL? {
        containerURL?.appendingPathComponent(pendingReferenceFilename)
    }

    static func writePendingReference(_ data: Data) throws {
        guard let url = pendingReferenceURL else {
            throw CocoaError(.fileNoSuchFile)
        }
        try data.write(to: url, options: .atomic)
    }

    static func readPendingReference() -> Data? {
        guard let url = pendingReferenceURL,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func clearPendingReference() {
        guard let url = pendingReferenceURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
