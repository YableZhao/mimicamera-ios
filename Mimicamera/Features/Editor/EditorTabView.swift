import SwiftUI

/// Root of the Edit tab. Library view is the landing; picking a photo (or
/// reopening a recent edit) pushes the `EditorView` onto the stack.
struct EditorTabView: View {
    @State private var picked: PickedPhoto?

    struct PickedPhoto: Hashable {
        let image: UIImage
        let assetLocalIdentifier: String?
    }

    var body: some View {
        NavigationStack {
            LibraryView { image, assetID in
                picked = PickedPhoto(image: image, assetLocalIdentifier: assetID)
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: Binding(
                get: { picked != nil },
                set: { if !$0 { picked = nil } }
            )) {
                if let picked {
                    EditorView(source: picked.image, assetLocalIdentifier: picked.assetLocalIdentifier)
                }
            }
        }
    }
}
