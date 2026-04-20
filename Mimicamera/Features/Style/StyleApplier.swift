import Foundation
import Observation

/// Orchestrates the full "user picked a reference → backend fits a LUT →
/// StyleStore is updated" pipeline. Lives at the view layer (one per tab)
/// and talks to the shared `StyleStore`. Splitting this out of the view
/// lets the camera tab and editor tab share identical fit logic while
/// owning their own transient status/toast state.
///
/// Why not put this on `StyleStore` itself? StyleStore is the *shared*
/// source of truth; every surface reads from it. If fit status lived
/// there too, a pick in one tab would flash "Fitting colours…" in the
/// other tab. Keeping the orchestrator per-view is the smaller blast
/// radius.
@Observable
@MainActor
final class StyleApplier {
    enum FitStatus: Equatable {
        case idle
        case curating
        case fitting
        case failed(String)
    }

    let style: StyleStore
    var status: FitStatus = .idle

    /// Views inject a toast emitter; the applier stays free of UI concerns.
    var onToast: ((String, TimeInterval) -> Void)?

    private let clientProvider: () -> MimicameraClient

    init(style: StyleStore, clientProvider: @escaping () -> MimicameraClient) {
        self.style = style
        self.clientProvider = clientProvider
    }

    // MARK: - Public entry points

    /// Apply a bundled curated look. Synchronous — no backend involved.
    func applyCurated(_ look: CuratedLook) throws {
        try style.loadBundledLUT(named: look.id, description: look.description)
    }

    /// Apply the current live-clipboard URL (or any URL) through `/fit_lut`.
    func applyURL(_ urlString: String) async {
        status = .fitting
        do {
            let jpeg = try await URLReferenceFetcher.fetchJPEG(from: urlString)
            await applyReferences([jpeg])
        } catch {
            let msg = error.localizedDescription
            status = .failed(msg)
            onToast?("Couldn't fetch URL: \(msg)", 4.5)
            try? await Task.sleep(for: .seconds(3))
            status = .idle
        }
    }

    /// Apply one or more reference JPEGs. >1 → curate first, then fit.
    func applyReferences(_ references: [Data]) async {
        do {
            var subset = references
            var curatedName: String?
            var curatedDescription: String?

            let client = clientProvider()

            if references.count > 1 {
                status = .curating
                let curation = try await client.curate(references: references)
                let clamped = curation.selectedIndices.filter { (0..<references.count).contains($0) }
                let picked = clamped.isEmpty
                    ? Array(0..<min(references.count, 5))
                    : clamped
                subset = picked.map { references[$0] }
                curatedName = curation.styleName
                curatedDescription = curation.styleDescription
            }

            status = .fitting
            let result = try await client.fitLUT(references: subset)
            let description = references.count > 1 ? curatedDescription : result.styleDescription
            try style.applyFittedCube(
                text: result.cubeText,
                name: curatedName ?? (references.count > 1 ? "Your Style" : result.styleName),
                description: description
            )
            status = .idle
            if let desc = description, !desc.isEmpty {
                onToast?(desc, 3.0)
            }
        } catch {
            let msg = String(describing: error)
            status = .failed(msg)
            onToast?("Fit failed: \(String(msg.prefix(200)))", 5.0)
            try? await Task.sleep(for: .seconds(3))
            status = .idle
        }
    }

    /// Consume any pending reference dropped by the Share Extension.
    func consumePendingSharedImage() {
        guard let data = SharedContainer.readPendingReference() else { return }
        SharedContainer.clearPendingReference()
        Task { await applyReferences([data]) }
    }
}
