import CoreImage
import Foundation
import Observation

/// Single source of truth for the currently-selected style. Shared across the
/// live-camera tab and the editor tab via SwiftUI's `@Environment`. Swapping
/// a look or dragging the intensity slider in either tab updates both.
///
/// Responsibilities this class OWNS:
///   - the fitted-LUT bytes (from a curated `.cube` or a backend `/fit_lut` response)
///   - the intensity α (0…1, blended in LUT space toward identity)
///   - the derived, blended LUT bytes + a `CIFilter` built from them
///   - the user-facing chip metadata (name + one-sentence description)
///
/// Responsibilities this class does NOT own:
///   - AVCaptureSession (lives in `LUTPipeline`)
///   - the static image being edited (lives in the editor view)
///   - Photos writes (lives in `CaptureWriter`)
@Observable
@MainActor
final class StyleStore {
    // MARK: - Public state

    var intensity: Float = 1.0 {
        didSet { rebuildBlendedLUT() }
    }

    private(set) var activeStyleName: String?
    private(set) var activeStyleDescription: String?

    /// Raw LUT data (RGBA floats) ready to stuff into `CIColorCube`. `nil` means identity.
    private(set) var blendedCubeData: Data?
    private(set) var cubeDimension: Int = 33

    /// Convenience wrapper — builds a `CIColorCube` filter whenever `blendedCubeData` is present.
    /// Rebuilt on every access; callers that need stable identity (e.g. per-frame capture)
    /// should cache the result for the duration of a frame.
    var currentFilter: CIFilter? {
        guard let data = blendedCubeData else { return nil }
        let filter = CIFilter(name: "CIColorCube")!
        filter.setValue(cubeDimension, forKey: "inputCubeDimension")
        filter.setValue(data, forKey: "inputCubeData")
        return filter
    }

    // MARK: - Private

    private var fittedCubeData: Data?
    private var identityCubeData: Data = CubeLUT.identityData(size: 33)

    // MARK: - Mutators

    /// Apply a fitted LUT returned by `mimicamera-api` (or baked locally).
    /// `text` is the raw `.cube` file contents.
    func applyFittedCube(
        text: String,
        name: String?,
        description: String? = nil
    ) throws {
        let (size, data) = try CubeLUT.parse(text: text)
        cubeDimension = size
        fittedCubeData = data
        identityCubeData = CubeLUT.identityData(size: size)
        activeStyleName = name
        activeStyleDescription = description
        rebuildBlendedLUT()
    }

    /// Load a bundled `.cube` (e.g. one of the six curated looks) and apply it.
    /// `styleDescription` overrides the inline TITLE when provided.
    func loadBundledLUT(
        named name: String,
        subdirectory: String = "CuratedLUTs",
        description: String? = nil
    ) throws {
        guard
            let url = Bundle.main.url(forResource: name, withExtension: "cube", subdirectory: subdirectory)
                  ?? Bundle.main.url(forResource: name, withExtension: "cube"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            throw CubeLUTError.parseFailure(line: 0)
        }
        let title = CubeLUT.title(in: text) ?? name
        try applyFittedCube(text: text, name: title, description: description)
    }

    /// Drop the current style and render input images unmodified.
    func clear() {
        fittedCubeData = nil
        blendedCubeData = nil
        activeStyleName = nil
        activeStyleDescription = nil
    }

    // MARK: - Internals

    private func rebuildBlendedLUT() {
        guard let fitted = fittedCubeData else {
            blendedCubeData = nil
            return
        }
        blendedCubeData = CubeLUT.blend(
            identity: identityCubeData,
            fitted: fitted,
            alpha: intensity
        )
    }
}
