import Foundation
import Observation

/// Remembers the last N photos the user edited, so the library landing can
/// show a thumbnail grid instead of an always-empty state. Persistence is
/// JSON-in-UserDefaults — enough for twelve PHAsset local identifiers plus
/// a cached style name. Real "edit history" (undo stacks, snapshots) is out
/// of scope for this build.
@Observable
@MainActor
final class RecentEditsStore {
    struct Entry: Codable, Identifiable, Hashable {
        let id: UUID
        let assetLocalIdentifier: String
        let styleName: String?
        let styleCuratedID: String?   // set when the applied style was a bundled look
        let createdAt: Date
    }

    private(set) var entries: [Entry] = []

    private let defaults: UserDefaults
    private let storageKey = "MimicameraRecentEdits.v1"
    private let maxEntries = 12

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// Append a new entry to the front, de-duplicating by asset ID so a photo
    /// edited repeatedly shows once with the latest style/timestamp.
    func record(assetLocalIdentifier: String, styleName: String?, styleCuratedID: String?) {
        let new = Entry(
            id: UUID(),
            assetLocalIdentifier: assetLocalIdentifier,
            styleName: styleName,
            styleCuratedID: styleCuratedID,
            createdAt: Date()
        )
        var next = entries.filter { $0.assetLocalIdentifier != assetLocalIdentifier }
        next.insert(new, at: 0)
        if next.count > maxEntries { next = Array(next.prefix(maxEntries)) }
        entries = next
        save()
    }

    func remove(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard
            let data = defaults.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([Entry].self, from: data)
        else {
            return
        }
        entries = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
