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

            let drawableSize = view.drawableSize
            let imageExtent = image.extent
            // Aspect-fill the incoming (already upright) image into the drawable.
            let scaleX = drawableSize.width / imageExtent.width
            let scaleY = drawableSize.height / imageExtent.height
            let scale = max(scaleX, scaleY)
            let scaled = image.transformed(by: .init(scaleX: scale, y: scale))
            let offsetX = (drawableSize.width - scaled.extent.width) / 2
            let offsetY = (drawableSize.height - scaled.extent.height) / 2
            let centered = scaled.transformed(by: .init(translationX: offsetX, y: offsetY))

            context.render(
                centered,
                to: drawable.texture,
                commandBuffer: commandBuffer,
                bounds: CGRect(origin: .zero, size: drawableSize),
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
