import AVFoundation
import CoreImage
import Observation

/// Core camera → CIColorCube → display pipeline. Owns the AVCaptureSession and
/// the currently-active LUT filter. The live loop is entirely on-device; the
/// fitted LUT comes from the backend once per reference change.
@Observable
@MainActor
final class LUTPipeline: NSObject {
    let captureSession = AVCaptureSession()
    private(set) var ciContext = CIContext(options: [.priorityRequestLow: false])
    private let sampleQueue = DispatchQueue(label: "mimicamera.sample", qos: .userInteractive)
    private let videoOutput = AVCaptureVideoDataOutput()

    private var currentFilter: CIFilter?
    private var currentSize: Int = 33
    private var fittedCubeData: Data?
    private var identityCubeData: Data = CubeLUT.identityData(size: 33)

    /// Intensity α, applied in LUT space. 0 = original, 1 = full style.
    var intensity: Float = 1.0 { didSet { rebuildBlendedFilter() } }

    /// Short name displayed in the top bar chip.
    var activeStyleName: String?

    /// The current CIImage being rendered. `CameraView` observes this via MTKView / SwiftUI.
    var latestCIImage: CIImage?

    // MARK: - Session lifecycle

    func start() async {
        guard await requestCameraPermission() else { return }
        configureSession()
        captureSession.startRunning()
    }

    func stop() {
        captureSession.stopRunning()
    }

    private func requestCameraPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    private func configureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1920x1080

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            captureSession.canAddInput(input)
        else {
            captureSession.commitConfiguration()
            return
        }
        captureSession.addInput(input)

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: sampleQueue)
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        // Once a LUT is applied, lock WB so it doesn't fight the reference's colour cast.
        if let device = try? lockedDevice(input.device) {
            if device.isWhiteBalanceModeSupported(.locked) {
                device.whiteBalanceMode = .locked
            }
            device.unlockForConfiguration()
        }

        captureSession.commitConfiguration()
    }

    private func lockedDevice(_ device: AVCaptureDevice) throws -> AVCaptureDevice {
        try device.lockForConfiguration()
        return device
    }

    // MARK: - LUT updates

    /// Replace the active LUT with a fitted cube returned by `mimicamera-api`.
    func applyFittedCube(cubeText: String, styleName: String?) throws {
        let (size, data) = try CubeLUT.parse(text: cubeText)
        currentSize = size
        fittedCubeData = data
        identityCubeData = CubeLUT.identityData(size: size)
        activeStyleName = styleName
        rebuildBlendedFilter()
    }

    /// Clear the LUT and fall back to identity (pass-through) rendering.
    func clearLUT() {
        fittedCubeData = nil
        currentFilter = nil
        activeStyleName = nil
    }

    private func rebuildBlendedFilter() {
        guard let fitted = fittedCubeData else {
            currentFilter = nil
            return
        }
        let blended = CubeLUT.blend(identity: identityCubeData, fitted: fitted, alpha: intensity)
        let filter = CIFilter(name: "CIColorCube")!
        filter.setValue(currentSize, forKey: "inputCubeDimension")
        filter.setValue(blended, forKey: "inputCubeData")
        currentFilter = filter
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension LUTPipeline: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var image = CIImage(cvPixelBuffer: pixelBuffer)
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let filter = self.currentFilter {
                filter.setValue(image, forKey: kCIInputImageKey)
                if let out = filter.outputImage { image = out }
            }
            self.latestCIImage = image
        }
    }
}
