import CoreImage
import Foundation

enum CubeLUTError: Error {
    case missingSizeHeader
    case wrongEntryCount(expected: Int, got: Int)
    case parseFailure(line: Int)
}

/// Parses the `.cube` format produced by `mimicamera-api` and builds a `CIColorCube` filter.
///
/// The `.cube` format writes entries with R varying fastest, then G, then B — which is
/// exactly what `CIColorCube`'s `inputCubeData` expects, so no reordering is needed.
/// `CIColorCube` wants `dimension³` RGBA float tuples in a contiguous `Data` buffer.
enum CubeLUT {
    static func parse(text: String) throws -> (size: Int, rgbaData: Data) {
        var size: Int? = nil
        var values: [Float] = []
        values.reserveCapacity(33 * 33 * 33 * 4)

        for (index, raw) in text.split(whereSeparator: { $0.isNewline }).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            let upper = line.uppercased()
            if upper.hasPrefix("LUT_3D_SIZE") {
                let parts = line.split(whereSeparator: { $0.isWhitespace })
                guard parts.count >= 2, let n = Int(parts[1]) else {
                    throw CubeLUTError.parseFailure(line: index + 1)
                }
                size = n
                continue
            }
            if upper.hasPrefix("TITLE") || upper.hasPrefix("DOMAIN_") || upper.hasPrefix("LUT_1D_SIZE") {
                continue
            }

            let parts = line.split(whereSeparator: { $0.isWhitespace })
            guard parts.count == 3,
                  let r = Float(parts[0]),
                  let g = Float(parts[1]),
                  let b = Float(parts[2]) else {
                continue
            }
            values.append(r)
            values.append(g)
            values.append(b)
            values.append(1.0)
        }

        guard let size else { throw CubeLUTError.missingSizeHeader }
        let expectedCells = size * size * size
        let actualCells = values.count / 4
        guard actualCells == expectedCells else {
            throw CubeLUTError.wrongEntryCount(expected: expectedCells, got: actualCells)
        }

        let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
        return (size, data)
    }

    static func makeFilter(fromCube text: String) throws -> CIFilter {
        let (size, data) = try parse(text: text)
        let filter = CIFilter(name: "CIColorCube")!
        filter.setValue(size, forKey: "inputCubeDimension")
        filter.setValue(data, forKey: "inputCubeData")
        return filter
    }

    /// Parses the `TITLE "..."` line out of a `.cube` file, if present.
    static func title(in text: String) -> String? {
        for raw in text.split(whereSeparator: { $0.isNewline }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.uppercased().hasPrefix("TITLE") else { continue }
            if let start = line.firstIndex(of: "\""),
               let end = line.lastIndex(of: "\""),
               start < end {
                return String(line[line.index(after: start)..<end])
            }
        }
        return nil
    }

    /// Linearly interpolates two equal-sized LUT data buffers in LUT space.
    /// Used for the intensity slider: `blend(identity, fitted, alpha)`.
    static func blend(identity: Data, fitted: Data, alpha: Float) -> Data {
        precondition(identity.count == fitted.count, "LUT buffers must be the same length")
        let count = identity.count / MemoryLayout<Float>.stride
        var out = [Float](repeating: 0, count: count)
        identity.withUnsafeBytes { idBytes in
            fitted.withUnsafeBytes { fitBytes in
                let idPtr = idBytes.bindMemory(to: Float.self)
                let fitPtr = fitBytes.bindMemory(to: Float.self)
                for i in 0..<count {
                    out[i] = idPtr[i] * (1 - alpha) + fitPtr[i] * alpha
                }
            }
        }
        return out.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Builds an identity LUT as RGBA Data for the given cube dimension.
    static func identityData(size: Int) -> Data {
        var values = [Float]()
        values.reserveCapacity(size * size * size * 4)
        let denom = Float(size - 1)
        for b in 0..<size {
            let bv = Float(b) / denom
            for g in 0..<size {
                let gv = Float(g) / denom
                for r in 0..<size {
                    let rv = Float(r) / denom
                    values.append(rv)
                    values.append(gv)
                    values.append(bv)
                    values.append(1.0)
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
