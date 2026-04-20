import SwiftUI

/// Root of the Edit tab. Library view is the landing; picking a photo pushes
/// the `EditorView` onto the stack so the style-chip and reference strip
/// can live full-surface.
struct EditorTabView: View {
    @State private var pickedImage: UIImage?

    var body: some View {
        NavigationStack {
            LibraryView(onPick: { image in pickedImage = image })
                .navigationTitle("Edit")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(isPresented: pickedImagePresented) {
                    if let pickedImage {
                        EditorView(source: pickedImage)
                    }
                }
        }
    }

    private var pickedImagePresented: Binding<Bool> {
        Binding(
            get: { pickedImage != nil },
            set: { if !$0 { pickedImage = nil } }
        )
    }
}
