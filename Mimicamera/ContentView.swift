import SwiftUI

struct ContentView: View {
    @State private var pipeline = LUTPipeline()

    var body: some View {
        ZStack {
            CameraView(pipeline: pipeline)
                .ignoresSafeArea()
            VStack {
                TopBar(styleName: pipeline.activeStyleName)
                Spacer()
                ShutterRow()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .task {
            await pipeline.start()
        }
    }
}

private struct TopBar: View {
    let styleName: String?

    var body: some View {
        HStack {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
            Text(styleName ?? "Pick a look")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
