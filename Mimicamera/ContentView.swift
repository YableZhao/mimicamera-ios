import SwiftUI

struct ContentView: View {
    @State private var pipeline = LUTPipeline()
    @State private var isComparingOriginal = false
    @State private var intensityBeforeCompare: Float = 1.0

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
                    comparing: isComparingOriginal
                )
                Spacer()
                if pipeline.activeStyleName != nil {
                    IntensitySlider(value: Binding(
                        get: { Double(pipeline.intensity) },
                        set: { pipeline.intensity = Float($0) }
                    ))
                    .padding(.bottom, 20)
                    .transition(.opacity)
                }
                ShutterRow()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .task {
            try? pipeline.loadBundledLUT(named: "demo-warm")
            await pipeline.start()
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
}

private struct TopBar: View {
    let styleName: String?
    let intensity: Float
    let comparing: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
            Text(comparing ? "Original" : (styleName ?? "Pick a look"))
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
            if styleName != nil && !comparing {
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
}

private struct IntensitySlider: View {
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 12) {
            Text("0")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
            Slider(value: $value, in: 0...1)
                .tint(Color(red: 0.82, green: 0.29, blue: 0.23))
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
    var body: some View {
        HStack {
            Spacer()
            Button(action: {}) {
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
        }
    }
}
