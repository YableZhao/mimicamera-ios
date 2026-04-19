import CoreImage
import Photos
import UIKit

enum CaptureWriterError: Error {
    case cannotRender
    case permissionDenied
    case saveFailed(Error)
}

/// Writes the unstyled-original and styled images to Photos as two
/// separate assets. Called from the shutter tap; Photos add-only
/// permission is prompted lazily on first capture.
actor CaptureWriter {
    private let ciContext: CIContext

    init(ciContext: CIContext = CIContext()) {
        self.ciContext = ciContext
    }

    func saveDualCapture(original: CIImage, styled: CIImage) async throws {
        try await ensurePermission()
        let originalJPEG = try render(image: original)
        let styledJPEG = try render(image: styled)
        try await save(jpegData: originalJPEG)
        try await save(jpegData: styledJPEG)
    }

    private func render(image: CIImage) throws -> Data {
        guard let cg = ciContext.createCGImage(image, from: image.extent) else {
            throw CaptureWriterError.cannotRender
        }
        let ui = UIImage(cgImage: cg)
        guard let jpeg = ui.jpegData(compressionQuality: 0.92) else {
            throw CaptureWriterError.cannotRender
        }
        return jpeg
    }

    private func ensurePermission() async throws {
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch current {
        case .authorized, .limited:
            return
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard granted == .authorized || granted == .limited else {
                throw CaptureWriterError.permissionDenied
            }
        default:
            throw CaptureWriterError.permissionDenied
        }
    }

    private func save(jpegData: Data) async throws {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: jpegData, options: nil)
            }
        } catch {
            throw CaptureWriterError.saveFailed(error)
        }
    }
}
