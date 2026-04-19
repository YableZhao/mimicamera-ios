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
    @State private var settings = SettingsStore()
    @State private var isEditingBackendURL = false
    @State private var backendHealth: BackendHealth = .unknown

    enum BackendHealth: Equatable {
        case unknown, reachable, unreachable
    }

    private let captureWriter = CaptureWriter()
    private var client: MimicameraClient {
        MimicameraClient(baseURL: settings.apiBaseURL)
    }

    enum FitStatus: Equatable {
        case idle
        case curating
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
                if backendHealth == .unreachable {
                    BackendOfflineBanner(url: settings.apiBase) {
                        isEditingBackendURL = true
                    }
                    .padding(.top, 6)
                }
                Spacer()
                if pipeline.activeStyleName != nil && fitStatus == ContentView.FitStatus.idle {
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
                try? pipeline.loadBundledLUT(named: first.id, styleDescription: first.description)
                selectedLookID = first.id
            }
            await pipeline.start()
            await pingBackend()
        }
        .onChange(of: settings.apiBase) { _, _ in
            Task { await pingBackend() }
        }
        .sheet(isPresented: $isPickingReference) {
            ReferencePicker(selectionLimit: 5) { datas in
                isPickingReference = false
                guard !datas.isEmpty else { return }
                Task { await curateAndFit(references: datas) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isEditingBackendURL) {
            BackendURLEditor(settings: settings)
                .presentationDetents([.fraction(0.32)])
        }
        .onShake { isEditingBackendURL = true }
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
            try pipeline.loadBundledLUT(named: look.id, styleDescription: look.description)
            selectedLookID = look.id
            Haptics.lightImpact()
            Task { await showToast(look.description, duration: 2.2) }
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
    private func showToast(_ text: String, duration: Double = 2.0) async {
        captureToast = text
        try? await Task.sleep(for: .seconds(duration))
        // Only clear if no newer toast replaced us.
        if captureToast == text {
            captureToast = nil
        }
    }

    @MainActor
    private func showToast(_ text: String?, duration: Double = 2.0) async {
        if let text, !text.isEmpty {
            await showToast(text, duration: duration)
        }
    }

    private func pingBackend() async {
        let url = settings.apiBaseURL.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.timeoutInterval = 2.0
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            backendHealth = ((response as? HTTPURLResponse)?.statusCode == 200) ? .reachable : .unreachable
        } catch {
            backendHealth = .unreachable
        }
    }

    private func curateAndFit(references: [Data]) async {
        do {
            var subset = references
            var curatedName: String?
            var curatedDescription: String?

            if references.count > 1 {
                fitStatus = .curating
                let curation = try await client.curate(references: references)
                let clamped = curation.selectedIndices.filter { (0..<references.count).contains($0) }
                let picked = clamped.isEmpty
                    ? Array(0..<min(references.count, 5))
                    : clamped
                subset = picked.map { references[$0] }
                curatedName = curation.styleName
                curatedDescription = curation.styleDescription
            }

            fitStatus = .fitting
            let result = try await client.fitLUT(references: subset)
            selectedLookID = nil  // user-supplied look, not a bundled one
            let description = references.count > 1 ? curatedDescription : result.styleDescription
            try pipeline.applyFittedCube(
                cubeText: result.cubeText,
                styleName: curatedName ?? (references.count > 1 ? "Your Style" : result.styleName),
                styleDescription: description
            )
            fitStatus = .idle
            if let desc = description, !desc.isEmpty {
                Task { await showToast(desc, duration: 3.0) }
            }
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
        case .curating: return "Reading the style…"
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

private struct BackendOfflineBanner: View {
    let url: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Backend offline · \(url)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.black.opacity(0.5), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

private struct BackendURLEditor: View {
    @Bindable var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Backend base URL") {
                    TextField("http://host:port", text: $settings.apiBase)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                }
                Section {
                    Button("Reset to default") {
                        settings.apiBase = SettingsStore.defaultAPIBase
                    }
                    .foregroundStyle(.secondary)
                } footer: {
                    Text("Shake the device to reopen this panel. The default assumes the backend runs on the Mac that shipped this build; update after switching networks.")
                }
            }
            .navigationTitle("Backend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
