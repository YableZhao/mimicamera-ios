import UIKit
import UniformTypeIdentifiers

/// Minimal share-extension UI: as soon as the sheet is presented we load the
/// first image attachment, re-encode it as JPEG, drop it into the App Group
/// shared container, and open the main app via the `mimicamera://` URL scheme.
///
/// The visible confirmation is intentionally terse — the user expects Share
/// Extensions to be fast. A single line, a red accent, no forms.
final class ShareViewController: UIViewController {
    private let messageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .label
        label.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        label.text = "Saving to Mimicamera…"
        return label
    }()

    private let spinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .medium)
        s.translatesAutoresizingMaskIntoConstraints = false
        s.startAnimating()
        return s
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.addSubview(messageLabel)
        view.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -16),
            messageLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 12),
            messageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])

        Task { await processAttachments() }
    }

    private func processAttachments() async {
        defer { completeRequest() }

        guard let attachments = (extensionContext?.inputItems.first as? NSExtensionItem)?.attachments,
              let provider = attachments.first(where: {
                  $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
                  || $0.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier)
                  || $0.hasItemConformingToTypeIdentifier(UTType.png.identifier)
              })
        else {
            await MainActor.run { updateMessage("No image in that share") }
            try? await Task.sleep(nanoseconds: 900_000_000)
            return
        }

        do {
            let data = try await loadImageData(from: provider)
            guard let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.9) else {
                await MainActor.run { updateMessage("That image couldn't be re-encoded") }
                try? await Task.sleep(nanoseconds: 900_000_000)
                return
            }
            try SharedContainer.writePendingReference(jpeg)
            await MainActor.run { updateMessage("Opening Mimicamera…") }
            await openMainApp()
        } catch {
            await MainActor.run { updateMessage("Couldn't save: \(error.localizedDescription)") }
            try? await Task.sleep(nanoseconds: 900_000_000)
        }
    }

    private func loadImageData(from provider: NSItemProvider) async throws -> Data {
        // Prefer the raw bytes; fall back to a UIImage load for generic providers
        // (some apps hand us a file URL, others a UIImage, others raw Data).
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            return try await provider.loadDataRepresentation(for: .image)
        }
        throw NSError(domain: "MimicameraShareExtension", code: -1)
    }

    private func updateMessage(_ text: String) {
        messageLabel.text = text
    }

    private func openMainApp() async {
        guard let url = URL(string: "mimicamera://fit?source=share") else { return }
        await MainActor.run {
            var responder: UIResponder? = self
            while let next = responder {
                if let application = next as? UIApplication {
                    application.open(url, options: [:], completionHandler: nil)
                    return
                }
                responder = next.next
            }
            // Fallback — some iOS versions wall off the walk-up above.
            if let url = URL(string: "mimicamera://fit?source=share") {
                self.extensionContext?.open(url, completionHandler: nil)
            }
        }
    }

    private func completeRequest() {
        Task { @MainActor in
            extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}

private extension NSItemProvider {
    /// Async wrapper around loadDataRepresentation(forTypeIdentifier:) so the
    /// share extension's entry point can await it directly.
    func loadDataRepresentation(for type: UTType) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: NSError(domain: "MimicameraShareExtension", code: -2))
                }
            }
        }
    }
}
