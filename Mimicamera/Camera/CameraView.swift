import MetalKit
import SwiftUI

/// Metal-backed preview surface. `LUTPipeline` updates `latestCIImage` from the
/// capture queue; this view observes it and draws into an `MTKView`.
struct CameraView: UIViewRepresentable {
    let pipeline: LUTPipeline

    func makeCoordinator() -> Coordinator {
        Coordinator(pipeline: pipeline)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.framebufferOnly = false
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 30
        view.delegate = context.coordinator
        context.coordinator.attach(view: view)
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.pipeline = pipeline
    }

    @MainActor
    final class Coordinator: NSObject, MTKViewDelegate {
        var pipeline: LUTPipeline
        private var commandQueue: MTLCommandQueue?
        private var context: CIContext?

        init(pipeline: LUTPipeline) {
            self.pipeline = pipeline
            super.init()
        }

        func attach(view: MTKView) {
            guard let device = view.device else { return }
            commandQueue = device.makeCommandQueue()
            context = CIContext(mtlDevice: device)
        }

        nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        nonisolated func draw(in view: MTKView) {
            Task { @MainActor [weak self] in
                self?.render(view: view)
            }
        }

        private func render(view: MTKView) {
            guard
                let drawable = view.currentDrawable,
                let commandBuffer = commandQueue?.makeCommandBuffer(),
                let image = pipeline.latestCIImage,
                let context = context
            else { return }

            let bounds = CGRect(origin: .zero, size: view.drawableSize)
            let scaled = image
                .cropped(to: image.extent)
                .transformed(by: .init(rotationAngle: -.pi / 2))

            context.render(
                scaled,
                to: drawable.texture,
                commandBuffer: commandBuffer,
                bounds: bounds,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
