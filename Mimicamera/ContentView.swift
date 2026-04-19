import SwiftUI

struct ContentView: View {
    @State private var pipeline = LUTPipeline()
    @State private var isComparingOriginal = false
    @State private var intensityBeforeCompare: Float = 1.0
    @State private var isPickingReference = false
    @State private var fitStatus: FitStatus = .idle
    @State private var isFlashing = false
    @State private var captureToast: String?
    @State private var curatedLooks: [CuratedLook] = []
    @State private var selectedLookID: String?

    private let apiBase: URL = URL(string: "http://127.0.0.1:8000")!
    private let captureWriter = CaptureWriter()
    private var client: MimicameraClient {
        MimicameraClient(baseURL: apiBase)
    }

    enum FitStatus: Equatable {
        case idle
        case fitting
        case failed(String)
    }

    var body: some View {
        ZStack {
            CameraView(pipeline: pipeline)
                .ignoresSafeArea()
                .onLongPressGesture(
                    minimumDuration: 0.15,
                    maximumDistance: 40,
                    perform: {},
                    onPressingChanged: handleCompareGesture
                )

            VStack {
                TopBar(
                    styleName: pipeline.activeStyleName,
                    intensity: pipeline.intensity,
                    comparing: isComparingOriginal,
                    status: fitStatus
                )
                Spacer()
                if pipeline.activeStyleName != nil && fitStatus == .idle {
                    IntensitySlider(value: Binding(
                        get: { Double(pipeline.intensity) },
                        set: { pipeline.intensity = Float($0) }
                    ))
                    .padding(.bottom, 12)
                    .transition(.opacity)
                }
                if !curatedLooks.isEmpty {
                    ReferenceStrip(
                        looks: curatedLooks,
                        selectedID: selectedLookID,
                        onSelect: selectCuratedLook
                    )
                    .padding(.bottom, 8)
                }
                ShutterRow(
                    onPickReference: { isPickingReference = true },
                    onShutter: { Task { await handleShutter() } }
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)

            if let toast = captureToast {
                ToastBanner(text: toast)
                    .transition(.opacity)
            }

            Color.white
                .ignoresSafeArea()
                .opacity(isFlashing ? 0.6 : 0)
                .animation(.easeOut(duration: 0.12), value: isFlashing)
                .allowsHitTesting(false)
        }
        .task {
            curatedLooks = CuratedLooks.load()
            if let first = curatedLooks.first {
                try? pipeline.loadBundledLUT(named: first.id)
                selectedLookID = first.id
            }
            await pipeline.start()
        }
        .sheet(isPresented: $isPickingReference) {
            ReferencePicker(selectionLimit: 1) { datas in
                isPickingReference = false
                guard let first = datas.first else { return }
                Task { await fitAndApply(reference: first) }
            }
            .ignoresSafeArea()
        }
    }

    private func handleCompareGesture(isPressing: Bool) {
        if isPressing && !isComparingOriginal {
            intensityBeforeCompare = pipeline.intensity
            pipeline.intensity = 0
            isComparingOriginal = true
        } else if !isPressing && isComparingOriginal {
            pipeline.intensity = intensityBeforeCompare
            isComparingOriginal = false
        }
    }

    private func selectCuratedLook(_ look: CuratedLook) {
        do {
            try pipeline.loadBundledLUT(named: look.id)
            selectedLookID = look.id
            Haptics.lightImpact()
        } catch {
            fitStatus = .failed("Could not load \(look.name)")
            Task {
                try? await Task.sleep(for: .seconds(2))
                fitStatus = .idle
            }
        }
    }

    private func handleShutter() async {
        guard let original = pipeline.latestOriginalImage,
              let styled = pipeline.latestCIImage else { return }
        Haptics.rigidImpact()
        await flash()
        do {
            try await captureWriter.saveDualCapture(original: original, styled: styled)
            Haptics.success()
            await showToast("Saved original + styled to Photos")
        } catch {
            Haptics.error()
            await showToast("Save failed: \(error)")
        }
    }

    @MainActor
    private func flash() async {
        isFlashing = true
        try? await Task.sleep(for: .milliseconds(130))
        isFlashing = false
    }

    @MainActor
    private func showToast(_ text: String) async {
        captureToast = text
        try? await Task.sleep(for: .seconds(2))
        captureToast = nil
    }

    private func fitAndApply(reference: Data) async {
        fitStatus = .fitting
        do {
            let result = try await client.fitLUT(references: [reference])
            try pipeline.applyFittedCube(cubeText: result.cubeText, styleName: result.styleName)
            fitStatus = .idle
        } catch {
            fitStatus = .failed(String(describing: error))
            try? await Task.sleep(for: .seconds(3))
            fitStatus = .idle
        }
    }
}

private struct TopBar: View {
    let styleName: String?
    let intensity: Float
    let comparing: Bool
    let status: ContentView.FitStatus

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
            if styleName != nil && !comparing && status == .idle {
                Text("\(Int(intensity * 100))%")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.35), in: .capsule)
    }

    private var label: String {
        if comparing { return "Original" }
        switch status {
        case .fitting: return "Fitting colours…"
        case .failed(let msg): return "Fit failed: \(msg.prefix(40))…"
        case .idle: return styleName ?? "Pick a look"
        }
    }
}

private struct IntensitySlider: View {
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
                    // Haptic tick when crossing the unity point.
                    let crossedUnity =
                        (lastNotchedValue < 1.0 && newValue >= 1.0) ||
                        (lastNotchedValue >= 1.0 && newValue < 1.0)
                    if crossedUnity {
                        Haptics.lightImpact()
                    }
                    lastNotchedValue = newValue
                }
            Text("1")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.35), in: .capsule)
    }
}

private struct ShutterRow: View {
    let onPickReference: () -> Void
    let onShutter: () -> Void

    var body: some View {
        HStack {
            Button(action: onPickReference) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 48, height: 48)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            Button(action: onShutter) {
                Circle()
                    .strokeBorder(.white, lineWidth: 3)
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle()
                            .fill(Color(red: 0.82, green: 0.29, blue: 0.23))
                            .padding(6)
                    )
            }
            .buttonStyle(.plain)
            Spacer()
            Color.clear.frame(width: 48, height: 48)
        }
    }
}

private struct ToastBanner: View {
    let text: String

    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.black.opacity(0.6), in: .capsule)
                .padding(.bottom, 140)
        }
        .allowsHitTesting(false)
    }
}
