import Foundation

struct CuratedLook: Identifiable, Hashable, Decodable {
    let id: String
    let name: String
    let description: String
}

enum CuratedLooks {
    /// Reads `CuratedLUTs/manifest.json` from the app bundle and returns the
    /// six hand-picked photographer looks.
    static func load() -> [CuratedLook] {
        let candidates = [
            Bundle.main.url(forResource: "manifest", withExtension: "json", subdirectory: "CuratedLUTs"),
            Bundle.main.url(forResource: "manifest", withExtension: "json"),
        ]
        guard let url = candidates.compactMap({ $0 }).first,
              let data = try? Data(contentsOf: url),
              let container = try? JSONDecoder().decode(Container.self, from: data) else {
            return []
        }
        return container.looks
    }

    private struct Container: Decodable {
        let looks: [CuratedLook]
    }
}
