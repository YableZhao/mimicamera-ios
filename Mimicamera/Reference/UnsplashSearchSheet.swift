import SwiftUI

/// Full-screen sheet for searching Unsplash + picking a photographer's shot.
/// Mimics the visual language of the curated strip — dark chrome, monospaced
/// metadata, photographic-red accent — so the two discovery surfaces feel
/// continuous.
struct UnsplashSearchSheet: View {
    let client: MimicameraClient
    let onPick: (UnsplashPhoto) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = "moody portrait"
    @State private var results: [UnsplashPhoto] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var keyed: Bool = true

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBar(query: $query, isLoading: isLoading) {
                    Task { await runSearch() }
                }
                if !keyed {
                    FallbackHint()
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.9))
                        .padding(.horizontal, 16)
                }
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(results) { photo in
                            PhotoTile(photo: photo) {
                                onPick(photo)
                                dismiss()
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Unsplash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                if results.isEmpty { await runSearch() }
            }
        }
    }

    private func runSearch() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await client.searchUnsplash(query: query)
            self.results = response.results
            self.keyed = response.keyed
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
        }
    }
}

private struct SearchBar: View {
    @Binding var query: String
    let isLoading: Bool
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search photographers or moods", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(onSubmit)
            if isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quaternary, in: .capsule)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

private struct FallbackHint: View {
    var body: some View {
        Text("Running in demo mode — set UNSPLASH_ACCESS_KEY on the backend for live search.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 6)
    }
}

private struct PhotoTile: View {
    let photo: UnsplashPhoto
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                AsyncImage(url: URL(string: photo.thumbnailURL)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Color.gray.opacity(0.2).overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        )
                    case .empty:
                        Color.gray.opacity(0.1).overlay(ProgressView())
                    @unknown default:
                        Color.gray.opacity(0.2)
                    }
                }
                .frame(height: 220)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(photo.photographerName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let desc = photo.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
    }
}
