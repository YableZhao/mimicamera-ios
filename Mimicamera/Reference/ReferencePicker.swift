import PhotosUI
import SwiftUI

/// SwiftUI wrapper around `PHPickerViewController`. Returns JPEG `Data` for each
/// chosen image — ready to be uploaded to `mimicamera-api /fit_lut`.
struct ReferencePicker: UIViewControllerRepresentable {
    let selectionLimit: Int
    let onPicked: ([Data]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = selectionLimit
        config.preferredAssetRepresentationMode = .current
        let vc = PHPickerViewController(configuration: config)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: ([Data]) -> Void

        init(onPicked: @escaping ([Data]) -> Void) {
            self.onPicked = onPicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            Task { [onPicked] in
                let datas = await withTaskGroup(of: Data?.self) { group -> [Data] in
                    for result in results {
                        group.addTask {
                            await Self.loadJPEG(from: result.itemProvider)
                        }
                    }
                    var out: [Data] = []
                    for await item in group {
                        if let d = item { out.append(d) }
                    }
                    return out
                }
                await MainActor.run {
                    onPicked(datas)
                }
            }
        }

        private static func loadJPEG(from provider: NSItemProvider) async -> Data? {
            guard provider.canLoadObject(ofClass: UIImage.self) else { return nil }
            return await withCheckedContinuation { continuation in
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    guard let image = object as? UIImage,
                          let data = image.jpegData(compressionQuality: 0.9) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: data)
                }
            }
        }
    }
}
