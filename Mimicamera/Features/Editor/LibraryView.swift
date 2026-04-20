import PhotosUI
import SwiftUI

/// Empty-state library landing: a big "Pick a photo" CTA that opens
/// PHPicker. Commit 5 will grow this into a grid of recent edits.
struct LibraryView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var loadError: String?
    let onPick: (UIImage) -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "photo.stack")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Pick a photo to style")
                    .font(.system(.title3, design: .default, weight: .semibold))
                Text("Apply any look from your reference strip — curated, from Photos, Unsplash, a URL, or shared to Mimicamera.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            PhotosPicker(
                selection: $pickerItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                Label("Pick from Photos", systemImage: "photo.on.rectangle.angled")
                    .font(.system(.body, design: .default, weight: .medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.82, green: 0.29, blue: 0.23), in: .capsule)
                    .foregroundStyle(.white)
            }
            .padding(.top, 8)

            if let loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.9))
                    .padding(.horizontal, 40)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item: item) }
        }
    }

    private func load(item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                loadError = "Couldn't read that image."
                return
            }
            loadError = nil
            pickerItem = nil
            onPick(image)
        } catch {
            loadError = "Couldn't load: \(error.localizedDescription)"
        }
    }
}
