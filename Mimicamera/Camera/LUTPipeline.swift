import AVFoundation
import CoreImage
import Observation

/// AVCaptureSession wrapper that produces styled CIImages by applying the
/// current `StyleStore` filter to each frame. Intentionally owns *only* the
/// capture mechanics — style state lives in `StyleStore` so the editor tab
/// and the camera tab can share one source of truth.
@Observable
@MainActor
final class LUTPipeline: NSObject {
    let captureSession = AVCaptureSession()
    private(set) var ciContext = CIContext(options: [.priorityRequestLow: false])
    private let sampleQueue = DispatchQueue(label: "mimicamera.sample", qos: .userInteractive)
    private let videoOutput = AVCaptureVideoDataOutput()

    /// The shared style state. Initialised externally so every surface that
    /// reads it (camera preview, editor) sees the same bytes.
    private let style: StyleStore

    /// The current CIImage being rendered. `CameraView` observes this via MTKView / SwiftUI.
    var latestCIImage: CIImage?

    /// The most recent unstyled (pre-LUT) frame. Used for dual-capture.
    var latestOriginalImage: CIImage?

    init(style: StyleStore) {
        self.style = style
        super.init()
    }

    // MARK: - Session lifecycle

    func start() async {
        #if targetEnvironment(simulator)
        // The simulator has no camera. Push a synthetic gradient through the
        // current filter so the UI is driveable end-to-end without hardware.
        observeStyleForSimulator()
        renderSimulatorFrame()
        #else
        guard await requestCameraPermission() else { return }
        configureSession()
        captureSession.startRunning()
        #endif
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

    // MARK: - Simulator path

    #if targetEnvironment(simulator)
    private var simulatorObserverTask: Task<Void, Never>?

    /// Re-render the simulator gradient whenever the shared style changes
    /// (swap look, drag intensity) so the preview visibly reacts.
    private func observeStyleForSimulator() {
        simulatorObserverTask?.cancel()
        simulatorObserverTask = Task { @MainActor [weak self] in
            // Poll the observable — a light-touch way to wake on any change
            // without adding Combine plumbing.
            var lastSignature: String = ""
            while !Task.isCancelled {
                let sig = "\(self?.style.blendedCubeData?.count ?? 0)|\(self?.style.intensity ?? 0)"
                if sig != lastSignature {
                    self?.renderSimulatorFrame()
                    lastSignature = sig
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }

    private func renderSimulatorFrame() {
        let size = CGSize(width: 1170, height: 2532)
        guard let gradient = makeSpectrumGradient(size: size) else { return }
        var out = gradient
        if let filter = style.currentFilter {
            filter.setValue(gradient, forKey: kCIInputImageKey)
            if let processed = filter.outputImage { out = processed }
        }
        latestOriginalImage = gradient
        latestCIImage = out
    }

    private func makeSpectrumGradient(size: CGSize) -> CIImage? {
        let hueGradient = CIFilter(name: "CISmoothLinearGradient")
        hueGradient?.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
        hueGradient?.setValue(CIVector(x: size.width, y: size.height), forKey: "inputPoint1")
        hueGradient?.setValue(CIColor(red: 0.95, green: 0.45, blue: 0.25), forKey: "inputColor0")
        hueGradient?.setValue(CIColor(red: 0.15, green: 0.35, blue: 0.65), forKey: "inputColor1")
        return hueGradient?.outputImage?.cropped(to: CGRect(origin: .zero, size: size))
    }
    #endif
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
            if let filter = self.style.currentFilter {
                filter.setValue(original, forKey: kCIInputImageKey)
                if let out = filter.outputImage { styled = out }
            }
            self.latestOriginalImage = original
            self.latestCIImage = styled
        }
    }
}
