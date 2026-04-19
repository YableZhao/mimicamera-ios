import XCTest
@testable import Mimicamera

final class CubeLUTTests: XCTestCase {
    // MARK: - title(in:)

    func testTitleParsesDoubleQuotedValue() {
        let cube = """
        # header
        TITLE "Golden Hour"
        LUT_3D_SIZE 2
        """
        XCTAssertEqual(CubeLUT.title(in: cube), "Golden Hour")
    }

    func testTitleReturnsNilWhenMissing() {
        let cube = """
        # header
        LUT_3D_SIZE 2
        """
        XCTAssertNil(CubeLUT.title(in: cube))
    }

    // MARK: - parse

    func testParseValidTinyCube() throws {
        let cube = """
        TITLE "Tiny"
        LUT_3D_SIZE 2
        DOMAIN_MIN 0.0 0.0 0.0
        DOMAIN_MAX 1.0 1.0 1.0
        0.0 0.0 0.0
        1.0 0.0 0.0
        0.0 1.0 0.0
        1.0 1.0 0.0
        0.0 0.0 1.0
        1.0 0.0 1.0
        0.0 1.0 1.0
        1.0 1.0 1.0
        """
        let (size, data) = try CubeLUT.parse(text: cube)
        XCTAssertEqual(size, 2)
        XCTAssertEqual(data.count, 2 * 2 * 2 * 4 * MemoryLayout<Float>.stride)

        let floats: [Float] = data.withUnsafeBytes { buf in
            Array(buf.bindMemory(to: Float.self))
        }
        // First RGBA entry = first data line + alpha=1
        XCTAssertEqual(floats[0], 0.0)
        XCTAssertEqual(floats[1], 0.0)
        XCTAssertEqual(floats[2], 0.0)
        XCTAssertEqual(floats[3], 1.0)
        // Last RGBA entry = last data line + alpha=1
        XCTAssertEqual(floats[floats.count - 4], 1.0)
        XCTAssertEqual(floats[floats.count - 3], 1.0)
        XCTAssertEqual(floats[floats.count - 2], 1.0)
        XCTAssertEqual(floats[floats.count - 1], 1.0)
    }

    func testParseThrowsWhenSizeHeaderMissing() {
        let cube = """
        # no size
        0.0 0.0 0.0
        """
        XCTAssertThrowsError(try CubeLUT.parse(text: cube)) { error in
            guard case CubeLUTError.missingSizeHeader = error else {
                return XCTFail("expected .missingSizeHeader, got \(error)")
            }
        }
    }

    func testParseThrowsWhenEntryCountWrong() {
        // LUT_3D_SIZE 2 means we expect 8 RGB triples, but only 3 are supplied.
        let cube = """
        LUT_3D_SIZE 2
        0.0 0.0 0.0
        1.0 0.0 0.0
        0.0 1.0 0.0
        """
        XCTAssertThrowsError(try CubeLUT.parse(text: cube)) { error in
            guard case CubeLUTError.wrongEntryCount(let expected, let got) = error else {
                return XCTFail("expected .wrongEntryCount, got \(error)")
            }
            XCTAssertEqual(expected, 8)
            XCTAssertEqual(got, 3)
        }
    }

    func testParseSkipsCommentsAndBlankLines() throws {
        let cube = """

        # leading comment
        TITLE "Whitespace"

        LUT_3D_SIZE 2
        # another comment
        DOMAIN_MIN 0.0 0.0 0.0
        DOMAIN_MAX 1.0 1.0 1.0

        0.0 0.0 0.0
        1.0 0.0 0.0
        0.0 1.0 0.0
        1.0 1.0 0.0
        0.0 0.0 1.0
        1.0 0.0 1.0
        0.0 1.0 1.0
        1.0 1.0 1.0
        """
        let (size, _) = try CubeLUT.parse(text: cube)
        XCTAssertEqual(size, 2)
    }

    // MARK: - identityData

    func testIdentityDataHasCorrectSize() {
        let data = CubeLUT.identityData(size: 33)
        let expectedFloats = 33 * 33 * 33 * 4
        XCTAssertEqual(data.count, expectedFloats * MemoryLayout<Float>.stride)
    }

    func testIdentityDataBlackAndWhiteAtCorners() {
        let data = CubeLUT.identityData(size: 2)
        let floats: [Float] = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        // First cell (r=0, g=0, b=0) → (0,0,0,1)
        XCTAssertEqual(Array(floats[0..<4]), [0, 0, 0, 1])
        // Last cell (r=1, g=1, b=1) → (1,1,1,1)
        XCTAssertEqual(Array(floats[(floats.count - 4)..<floats.count]), [1, 1, 1, 1])
    }

    // MARK: - blend

    func testBlendIsLinearInAlpha() {
        let identity = CubeLUT.identityData(size: 2)
        // Build a "fitted" LUT that maps every cell to all-white.
        var fittedFloats = [Float]()
        for _ in 0..<(2 * 2 * 2) {
            fittedFloats += [1, 1, 1, 1]
        }
        let fitted = fittedFloats.withUnsafeBufferPointer { Data(buffer: $0) }

        let blend = CubeLUT.blend(identity: identity, fitted: fitted, alpha: 0.25)
        let blendFloats: [Float] = blend.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        // First cell: identity is (0,0,0,1), fitted is (1,1,1,1).
        // At alpha=0.25, result should be (0.25, 0.25, 0.25, 1.0).
        XCTAssertEqual(blendFloats[0], 0.25, accuracy: 1e-6)
        XCTAssertEqual(blendFloats[1], 0.25, accuracy: 1e-6)
        XCTAssertEqual(blendFloats[2], 0.25, accuracy: 1e-6)
        XCTAssertEqual(blendFloats[3], 1.0, accuracy: 1e-6)
    }
}
