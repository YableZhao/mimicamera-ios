import SwiftUI

/// Placeholder for the editor tab. Commit 3 will replace this with a real
/// photo-library grid + an editor surface that applies the current style
/// from `StyleStore` to a picked `UIImage`.
struct EditorTabView: View {
    @Environment(StyleStore.self) private var style

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.secondary)

                Text("Editor coming soon")
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.primary)

                Text("This is where your photo library will live. Pick a shot, apply any style from the Shoot tab, and export. Same LUTs, same strip, same references — just against a still image.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                if let name = style.activeStyleName {
                    VStack(spacing: 4) {
                        Text("Current style (shared with Shoot tab):")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(name)
                            .font(.system(.footnote, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.quaternary, in: .capsule)
                    }
                    .padding(.top, 16)
                }
            }
            .padding()
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
