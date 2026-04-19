import Foundation
import UIKit

enum URLReferenceFetcherError: Error, LocalizedError {
    case invalidURL
    case badStatus(Int)
    case notAnImage
    case empty

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "That doesn't look like a valid URL."
        case .badStatus(let code): return "Server returned \(code)."
        case .notAnImage: return "URL content isn't a recognised image format."
        case .empty: return "URL returned no data."
        }
    }
}

/// Fetches an arbitrary image URL and re-encodes it as JPEG so the backend's
/// /fit_lut + /curate endpoints (both of which accept JPEG multipart) can
/// consume it without having to know about HEIC, PNG, GIF, or WebP.
enum URLReferenceFetcher {
    static func fetchJPEG(from urlString: String, session: URLSession = .shared) async throws -> Data {
        guard
            let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty,
            let url = URL(string: trimmed),
            url.scheme?.lowercased().hasPrefix("http") == true
        else {
            throw URLReferenceFetcherError.invalidURL
        }

        var request = URLRequest(url: url)
        // Pretend to be a normal browser — many CDN endpoints 403 a bare
        // URLSession user-agent, especially Instagram / Cloudinary mirrors.
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 12

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLReferenceFetcherError.notAnImage
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLReferenceFetcherError.badStatus(http.statusCode)
        }
        guard !data.isEmpty else { throw URLReferenceFetcherError.empty }
        guard let image = UIImage(data: data),
              let jpeg = image.jpegData(compressionQuality: 0.9) else {
            throw URLReferenceFetcherError.notAnImage
        }
        return jpeg
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
