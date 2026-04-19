import Foundation

/// Persists per-user settings that can change between demo environments
/// without recompiling. Currently just the backend URL — shake the device
/// to edit.
@Observable
final class SettingsStore {
    static let defaultAPIBase = "http://10.43.135.138:8000"

    var apiBase: String {
        didSet {
            UserDefaults.standard.set(apiBase, forKey: Self.apiBaseKey)
        }
    }

    init() {
        self.apiBase = UserDefaults.standard.string(forKey: Self.apiBaseKey)
            ?? Self.defaultAPIBase
    }

    var apiBaseURL: URL {
        URL(string: apiBase) ?? URL(string: Self.defaultAPIBase)!
    }

    private static let apiBaseKey = "MimicameraAPIBase"
}
