import CoreImage
import SwiftUI
import UIKit

/// Static-image editor. The picked `UIImage` fills the surface; the
/// reference strip + picker icons below let the user swap styles from
/// curated looks, the Photos library, Unsplash search, or a pasted URL.
/// Intensity slider and long-press A/B ride alongside the live-camera
/// versions. Export saves both the original and the styled JPEGs to
/// Photos.
struct EditorView: View {
    let source: UIImage
    @Environment(StyleStore.self) private var style
    @Environment(\.dismiss) private var dismiss

    @State private var applier: StyleApplier?
    @State private var settings = SettingsStore()
    @State private var curatedLooks: [CuratedLook] = []
    @State private var selectedLookID: String?
    @State private var rendered: UIImage?

    @State private var isComparingOriginal = false
    @State private var intensityBeforeCompare: Float = 1.0

    @State private var isPickingReference = false
    @State private var isShowingUnsplash = false
    @State private var isPastingURL = false
    @State private var pastedURL: String = ""
    @State private var toast: String?
    @State private var exportedFlash = false

    private let ciContext = CIContext()

    private var client: MimicameraClient {
        MimicameraClient(baseURL: settings.apiBaseURL)
    }

    var body: some View {
        VStack(spacing: 0) {
            previewSurface
            controlStrip
        }
        .background(Color.black.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { Task { await export() } }) {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(applier?.status != .idle)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .center) {
            if exportedFlash {
                Color.white.ignoresSafeArea().opacity(0.4)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .task {
            if applier == nil {
                let app = StyleApplier(style: style, clientProvider: { MimicameraClient(baseURL: settings.apiBaseURL) })
                app.onToast = { text, duration in showToast(text, duration: duration) }
                applier = app
            }
            curatedLooks = CuratedLooks.load()
            if style.activeStyleName == nil, let first = curatedLooks.first {
                try? style.loadBundledLUT(named: first.id, description: first.description)
                selectedLookID = first.id
            } else {
                selectedLookID = curatedLooks.first(where: { $0.name == style.activeStyleName })?.id
            }
            rerender()
        }
        .onChange(of: style.blendedCubeData) { _, _ in rerender() }
        .sheet(isPresented: $isPickingReference) {
            ReferencePicker(selectionLimit: 5) { datas in
                isPickingReference = false
                guard !datas.isEmpty else { return }
                selectedLookID = nil
                Task { await applier?.applyReferences(datas) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isShowingUnsplash) {
            UnsplashSearchSheet(client: client) { photo in
                selectedLookID = nil
                Task { await applier?.applyURL(photo.fullURL) }
            }
        }
        .alert("Paste image URL", isPresented: $isPastingURL) {
            TextField("https://…", text: $pastedURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { pastedURL = "" }
            Button("Fit") {
                let url = pastedURL
                pastedURL = ""
                selectedLookID = nil
                Task { await applier?.applyURL(url) }
            }
        }
    }

    // MARK: - Preview surface (image + chip + long-press A/B + floating toast)

    private var previewSurface: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                Image(uiImage: rendered ?? source)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .contentShape(Rectangle())
                    .onLongPressGesture(
                        minimumDuration: 0.15,
                        maximumDistance: 40,
                        perform: {},
                        onPressingChanged: handleCompareGesture
                    )
                overlay
            }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        VStack {
            if let status = applier?.status, status != .idle || isComparingOriginal {
                chipLabel(status: status)
                    .padding(.top, 8)
            } else if let name = style.activeStyleName {
                StyleChip(name: name, intensity: style.intensity)
                    .padding(.top, 8)
            }
            Spacer()
            if let toast {
                ToastBanner(text: toast)
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    private func chipLabel(status: StyleApplier.FitStatus) -> some View {
        let text: String = {
            if isComparingOriginal { return "Original" }
            switch status {
            case .idle: return style.activeStyleName ?? "Pick a look"
            case .curating: return "Reading the style…"
            case .fitting: return "Fitting colours…"
            case .failed(let msg): return "Fit failed: \(String(msg.prefix(32)))…"
            }
        }()
        return Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.55), in: .capsule)
    }

    // MARK: - Control strip (reference strip + intensity + pick icons)

    private var controlStrip: some View {
        VStack(spacing: 10) {
            if style.activeStyleName != nil, applier?.status == .idle {
                IntensityPill(value: Binding(
                    get: { Double(style.intensity) },
                    set: { style.intensity = Float($0) }
                ))
            }
            if !curatedLooks.isEmpty {
                ReferenceStrip(
                    looks: curatedLooks,
                    selectedID: selectedLookID,
                    onSelect: selectCurated
                )
            }
            PickIconRow(
                onPhotos: { isPickingReference = true },
                onUnsplash: { isShowingUnsplash = true },
                onPaste: { preparePasteURL() }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
        .padding(.vertical, 10)
        .background(Color.black)
    }

    // MARK: - Actions

    private func selectCurated(_ look: CuratedLook) {
        do {
            try applier?.applyCurated(look)
            selectedLookID = look.id
            Haptics.lightImpact()
            showToast(look.description, duration: 2.2)
        } catch {
            showToast("Could not load \(look.name)", duration: 2)
        }
    }

    private func handleCompareGesture(isPressing: Bool) {
        if isPressing && !isComparingOriginal {
            intensityBeforeCompare = style.intensity
            style.intensity = 0
            isComparingOriginal = true
        } else if !isPressing && isComparingOriginal {
            style.intensity = intensityBeforeCompare
            isComparingOriginal = false
        }
    }

    private func preparePasteURL() {
        if let clip = UIPasteboard.general.string, clip.lowercased().hasPrefix("http") {
            pastedURL = clip
        }
        isPastingURL = true
    }

    private func export() async {
        guard let rendered else { return }
        let writer = CaptureWriter()
        guard let originalCI = CIImage(image: source),
              let styledCI = CIImage(image: rendered) else { return }
        Haptics.rigidImpact()
        withAnimation(.easeOut(duration: 0.12)) { exportedFlash = true }
        try? await Task.sleep(for: .milliseconds(130))
        withAnimation(.easeIn(duration: 0.12)) { exportedFlash = false }
        do {
            try await writer.saveDualCapture(original: originalCI, styled: styledCI)
            Haptics.success()
            showToast("Saved original + styled to Photos", duration: 2.5)
        } catch {
            Haptics.error()
            showToast("Save failed: \(error)", duration: 3)
        }
    }

    // MARK: - Rendering

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

    private func showToast(_ text: String?, duration: TimeInterval = 2.0) {
        guard let text, !text.isEmpty else { return }
        toast = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            if toast == text { toast = nil }
        }
    }
}

// MARK: - Reusable bits

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

private struct IntensityPill: View {
    @Binding var value: Double
    @State private var lastNotchedValue: Double = 1.0

    var body: some View {
        HStack(spacing: 12) {
            Text("0")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
            Slider(value: $value, in: 0...1)
                .tint(Color(red: 0.82, green: 0.29, blue: 0.23))
                .onChange(of: value) { _, newValue in
                    let crossedUnity =
                        (lastNotchedValue < 1.0 && newValue >= 1.0) ||
                        (lastNotchedValue >= 1.0 && newValue < 1.0)
                    if crossedUnity { Haptics.lightImpact() }
                    lastNotchedValue = newValue
                }
            Text("1")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.35), in: .capsule)
        .padding(.horizontal, 16)
    }
}

private struct PickIconRow: View {
    let onPhotos: () -> Void
    let onUnsplash: () -> Void
    let onPaste: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            pickButton(systemName: "photo.on.rectangle.angled", label: "Photos", action: onPhotos)
            pickButton(systemName: "magnifyingglass", label: "Unsplash", action: onUnsplash)
            pickButton(systemName: "link", label: "URL", action: onPaste)
            Spacer()
        }
    }

    private func pickButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemName)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.4), in: Circle())
                Text(label)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ToastBanner: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.black.opacity(0.6), in: .capsule)
    }
}
