import CoreImage
import SwiftUI
import UIKit

/// Static-image editor. The picked `UIImage` fills the surface; tapping a
/// curated look on the reference strip below re-applies `style.currentFilter`
/// to it. Intensity slider, reference pickers, and export land in commit 4.
struct EditorView: View {
    let source: UIImage
    @Environment(StyleStore.self) private var style
    @Environment(\.dismiss) private var dismiss

    @State private var curatedLooks: [CuratedLook] = []
    @State private var selectedLookID: String?
    @State private var rendered: UIImage?

    private let ciContext = CIContext()

    var body: some View {
        VStack(spacing: 0) {
            Color.black
                .ignoresSafeArea(edges: .top)
                .overlay {
                    Image(uiImage: rendered ?? source)
                        .resizable()
                        .scaledToFit()
                }
                .overlay(alignment: .top) {
                    if let name = style.activeStyleName {
                        StyleChip(name: name, intensity: style.intensity)
                            .padding(.top, 6)
                    }
                }

            VStack(spacing: 10) {
                if !curatedLooks.isEmpty {
                    ReferenceStrip(
                        looks: curatedLooks,
                        selectedID: selectedLookID,
                        onSelect: selectCuratedLook
                    )
                }
            }
            .padding(.vertical, 12)
            .background(Color.black)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            curatedLooks = CuratedLooks.load()
            if let first = curatedLooks.first, style.activeStyleName == nil {
                try? style.loadBundledLUT(named: first.id, description: first.description)
                selectedLookID = first.id
            } else {
                // Match the existing selection to whatever the shared store has, if possible.
                selectedLookID = curatedLooks.first(where: { $0.name == style.activeStyleName })?.id
            }
            rerender()
        }
        .onChange(of: style.blendedCubeData) { _, _ in rerender() }
    }

    private func selectCuratedLook(_ look: CuratedLook) {
        do {
            try style.loadBundledLUT(named: look.id, description: look.description)
            selectedLookID = look.id
            Haptics.lightImpact()
        } catch {
            // swallow — UI already shows the prior style
        }
    }

    private func rerender() {
        guard let ci = CIImage(image: source) else {
            rendered = source
            return
        }
        let filter = style.currentFilter
        let output: CIImage
        if let filter {
            filter.setValue(ci, forKey: kCIInputImageKey)
            output = filter.outputImage ?? ci
        } else {
            output = ci
        }
        if let cg = ciContext.createCGImage(output, from: output.extent) {
            rendered = UIImage(cgImage: cg, scale: source.scale, orientation: source.imageOrientation)
        } else {
            rendered = source
        }
    }
}

private struct StyleChip: View {
    let name: String
    let intensity: Float

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(.red).frame(width: 6, height: 6)
            Text(name)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
            Text("\(Int(intensity * 100))%")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.black.opacity(0.55), in: .capsule)
    }
}
