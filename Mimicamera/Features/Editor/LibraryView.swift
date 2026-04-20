import Photos
import PhotosUI
import SwiftUI

/// Library landing. When the user has no saved edits, shows a big "Pick
/// from Photos" CTA. Once they've exported at least one edit, shows a
/// grid of thumbnails above the CTA; tap a thumbnail to reopen that
/// photo in the editor.
struct LibraryView: View {
    @Environment(RecentEditsStore.self) private var recents
    @State private var pickerItem: PhotosPickerItem?
    @State private var loadError: String?

    /// Parent hands us the picked image + an optional PHAsset identifier so
    /// the editor can record it in RecentEditsStore on export.
    let onPick: (UIImage, String?) -> Void

    private let gridColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                if !recents.entries.isEmpty {
                    recentsSection
                } else {
                    emptyStateFooter
                }

                if let loadError {
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.9))
                        .padding(.horizontal, 40)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item: item) }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 14) {
            if recents.entries.isEmpty {
                Image(systemName: "photo.stack")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                Text(recents.entries.isEmpty ? "Pick a photo to style" : "Start something new")
                    .font(.system(.title3, design: .default, weight: .semibold))
                Text("Apply any look from the reference strip — curated, from Photos, Unsplash, a URL, or shared to Mimicamera.")
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
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.82, green: 0.29, blue: 0.23), in: .capsule)
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent edits")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)

            LazyVGrid(columns: gridColumns, spacing: 10) {
                ForEach(recents.entries) { entry in
                    RecentThumbnail(entry: entry) {
                        Task { await reopen(entry) }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            recents.remove(entry)
                        } label: {
                            Label("Remove from recents", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var emptyStateFooter: some View {
        Text("Your recent edits will appear here once you export.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.top, 8)
    }

    // MARK: - Actions

    private func load(item: PhotosPickerItem) async {
        do {
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                loadError = "Couldn't read that image."
                return
            }
            loadError = nil
            pickerItem = nil
            onPick(image, item.itemIdentifier)
        } catch {
            loadError = "Couldn't load: \(error.localizedDescription)"
        }
    }

    private func reopen(_ entry: RecentEditsStore.Entry) async {
        guard let asset = PHAsset.fetchAssets(
            withLocalIdentifiers: [entry.assetLocalIdentifier],
            options: nil
        ).firstObject else {
            loadError = "That photo is no longer in your library."
            recents.remove(entry)
            return
        }
        if let image = await PhotoAssetLoader.loadFull(asset: asset) {
            onPick(image, entry.assetLocalIdentifier)
        }
    }
}

// MARK: - Thumbnail tile

private struct RecentThumbnail: View {
    let entry: RecentEditsStore.Entry
    let onTap: () -> Void
    @State private var image: UIImage?

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                ZStack {
                    Color.gray.opacity(0.2)
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ProgressView()
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )

                if let name = entry.styleName {
                    Text(name)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.9))
                        .lineLimit(1)
                } else {
                    Text("No style")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .task {
            guard image == nil else { return }
            if let asset = PHAsset.fetchAssets(withLocalIdentifiers: [entry.assetLocalIdentifier], options: nil).firstObject {
                image = await PhotoAssetLoader.loadThumbnail(asset: asset, side: 240)
            }
        }
    }
}

// MARK: - PHAsset helpers

enum PhotoAssetLoader {
    static func loadThumbnail(asset: PHAsset, side: CGFloat) async -> UIImage? {
        await loadImage(asset: asset, targetSize: CGSize(width: side, height: side))
    }

    static func loadFull(asset: PHAsset) async -> UIImage? {
        await loadImage(asset: asset, targetSize: PHImageManagerMaximumSize)
    }

    private static func loadImage(asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = targetSize == PHImageManagerMaximumSize ? .highQualityFormat : .opportunistic
            options.resizeMode = .fast
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                // The callback may fire multiple times (degraded → final).
                // Resume on the first non-nil image to avoid double-resume.
                if !resumed, image != nil {
                    resumed = true
                    continuation.resume(returning: image)
                }
            }
        }
    }
}
