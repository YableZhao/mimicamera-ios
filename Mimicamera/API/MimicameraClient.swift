import Foundation

struct FitLUTResponse: Decodable {
    let mode: String
    let cubeB64: String
    let styleName: String
    let styleDescription: String
    let timingMs: Int

    enum CodingKeys: String, CodingKey {
        case mode
        case cubeB64 = "cube_b64"
        case styleName = "style_name"
        case styleDescription = "style_description"
        case timingMs = "timing_ms"
    }
}

enum MimicameraClientError: Error {
    case badStatus(code: Int, body: String)
    case decodingFailed(Error)
    case cubeDecodeFailed
}

/// Thin URLSession wrapper around `mimicamera-api`. No retries, no caching in v1.
actor MimicameraClient {
    let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    struct FitResult {
        let cubeText: String
        let styleName: String
        let styleDescription: String
        let timingMs: Int
        let mode: String
    }

    /// Fits a LUT from one or more reference JPEGs. Default mode is IDT; pass `.hist`
    /// for the per-channel fallback.
    func fitLUT(references: [Data], mode: Mode = .idt) async throws -> FitResult {
        var url = baseURL.appendingPathComponent("fit_lut")
        url.append(queryItems: [URLQueryItem(name: "mode", value: mode.rawValue)])

        let boundary = "MimicameraBoundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        for (index, jpeg) in references.enumerated() {
            body.append("--\(boundary)\r\n")
            body.append(#"Content-Disposition: form-data; name="references"; filename="ref-\#(index).jpg""# + "\r\n")
            body.append("Content-Type: image/jpeg\r\n\r\n")
            body.append(jpeg)
            body.append("\r\n")
        }
        body.append("--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MimicameraClientError.badStatus(code: -1, body: "no HTTPURLResponse")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MimicameraClientError.badStatus(
                code: http.statusCode,
                body: String(data: data, encoding: .utf8) ?? "<binary>"
            )
        }

        let decoded: FitLUTResponse
        do {
            decoded = try JSONDecoder().decode(FitLUTResponse.self, from: data)
        } catch {
            throw MimicameraClientError.decodingFailed(error)
        }

        guard let cubeBytes = Data(base64Encoded: decoded.cubeB64),
              let cubeText = String(data: cubeBytes, encoding: .utf8) else {
            throw MimicameraClientError.cubeDecodeFailed
        }

        return FitResult(
            cubeText: cubeText,
            styleName: decoded.styleName,
            styleDescription: decoded.styleDescription,
            timingMs: decoded.timingMs,
            mode: decoded.mode
        )
    }

    enum Mode: String, Sendable {
        case idt
        case hist
        case chroma
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let bytes = string.data(using: .utf8) {
            append(bytes)
        }
    }
}
