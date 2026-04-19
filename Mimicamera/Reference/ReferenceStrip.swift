import SwiftUI

/// Horizontal strip of curated looks. Tap a thumb to apply its LUT.
struct ReferenceStrip: View {
    let looks: [CuratedLook]
    let selectedID: String?
    let onSelect: (CuratedLook) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(looks) { look in
                    ThumbButton(
                        look: look,
                        isSelected: look.id == selectedID,
                        action: { onSelect(look) }
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 72)
    }
}

private struct ThumbButton: View {
    let look: CuratedLook
    let isSelected: Bool
    let action: () -> Void

    private var thumbnail: UIImage? {
        if let url = Bundle.main.url(forResource: look.id, withExtension: "jpg"),
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        return UIImage(named: look.id)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if let image = thumbnail {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    isSelected ? Color(red: 0.82, green: 0.29, blue: 0.23) : .white.opacity(0.2),
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.gray.opacity(0.3))
                        .frame(width: 48, height: 48)
                }
                Text(look.name)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.55))
                    .lineLimit(1)
                    .frame(maxWidth: 56)
            }
        }
        .buttonStyle(.plain)
    }
}
