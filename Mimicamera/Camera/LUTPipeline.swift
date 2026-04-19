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

    /// The most recent unstyled (pre-LUT) frame. Used for dual-capture.
    var latestOriginalImage: CIImage?

    // MARK: - Session lifecycle

    func start() async {
        #if targetEnvironment(simulator)
        // The simulator has no camera. Keep the pipeline idle so the UI can
        // be exercised without triggering the iOS camera-permission prompt.
        loadSimulatorTestImage()
        #else
        guard await requestCameraPermission() else { return }
        configureSession()
        captureSession.startRunning()
        #endif
    }

    #if targetEnvironment(simulator)
    /// Generates a broad-spectrum gradient CIImage and pushes it through the
    /// LUT so the simulator can show colour transforms without a real camera.
    private func loadSimulatorTestImage() {
        let size = CGSize(width: 1170, height: 2532)  // iPhone 17 Pro-like
        guard let gradient = makeSpectrumGradient(size: size) else { return }
        renderStatic(image: gradient)
    }

    private func makeSpectrumGradient(size: CGSize) -> CIImage? {
        let hueGradient = CIFilter(name: "CISmoothLinearGradient")
        hueGradient?.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
        hueGradient?.setValue(CIVector(x: size.width, y: size.height), forKey: "inputPoint1")
        hueGradient?.setValue(CIColor(red: 0.95, green: 0.45, blue: 0.25), forKey: "inputColor0")
        hueGradient?.setValue(CIColor(red: 0.15, green: 0.35, blue: 0.65), forKey: "inputColor1")
        return hueGradient?.outputImage?.cropped(to: CGRect(origin: .zero, size: size))
    }

    private func renderStatic(image: CIImage) {
        var out = image
        if let filter = currentFilter {
            filter.setValue(image, forKey: kCIInputImageKey)
            if let processed = filter.outputImage { out = processed }
        }
        latestOriginalImage = image
        latestCIImage = out
    }
    #endif

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

    /// Load a `.cube` file shipped inside the app bundle (e.g. one of the
    /// curated looks under `Resources/CuratedLUTs/`). The cube's TITLE line
    /// becomes the style chip label when `styleName` is not overridden.
    func loadBundledLUT(named name: String, subdirectory: String = "CuratedLUTs") throws {
        guard let url = Bundle.main.url(forResource: name, withExtension: "cube", subdirectory: subdirectory)
                ?? Bundle.main.url(forResource: name, withExtension: "cube") else {
            throw CubeLUTError.parseFailure(line: 0)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        let title = CubeLUT.title(in: text) ?? name
        try applyFittedCube(cubeText: text, styleName: title)
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

        #if targetEnvironment(simulator)
        // Re-render the static test image whenever the LUT changes so the
        // simulator preview updates visibly with intensity / style swaps.
        if let existing = latestCIImage, let gradient = makeSpectrumGradient(size: existing.extent.size) {
            renderStatic(image: gradient)
        }
        #endif
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
        // Back camera delivers landscape-right orientation; rotate to portrait
        // here rather than in the view so CameraView only renders upright images.
        let original = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        var styled = original
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let filter = self.currentFilter {
                filter.setValue(original, forKey: kCIInputImageKey)
                if let out = filter.outputImage { styled = out }
            }
            self.latestOriginalImage = original
            self.latestCIImage = styled
        }
    }
}
