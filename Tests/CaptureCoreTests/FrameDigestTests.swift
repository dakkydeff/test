import CaptureCore
import XCTest

final class FrameDigestTests: XCTestCase {
    func testSameBytesProduceSameDigest() {
        let bytes: [UInt8] = [0, 1, 2, 3, 255, 128, 64]
        XCTAssertEqual(FrameDigest(bytes), FrameDigest(bytes))
    }

    func testSingleByteDifferenceProducesDifferentDigest() {
        var other: [UInt8] = Array(repeating: 0x7F, count: 4096)
        let original = other
        other[2048] = 0x80
        XCTAssertNotEqual(FrameDigest(original), FrameDigest(other))
    }

    func testEmptyInputIsOffsetBasis() {
        XCTAssertEqual(FrameDigest([UInt8]()).value, 0xcbf2_9ce4_8422_2325)
        XCTAssertEqual(FrameDigest([UInt8]()), FrameDigest(value: FrameDigest.fnvOffsetBasis))
    }

    func testKnownFNV1a64Vectors() {
        XCTAssertEqual(FrameDigest(Array("a".utf8)).value, 0xaf63_dc4c_8601_ec8c)
        XCTAssertEqual(FrameDigest(Array("foobar".utf8)).value, 0x8594_4171_f739_67e8)
    }

    func testRawBufferInitMatchesCollectionInit() {
        let bytes = Array("KindleToPDF".utf8)
        let fromBuffer = bytes.withUnsafeBytes { FrameDigest(bytes: $0) }
        XCTAssertEqual(fromBuffer, FrameDigest(bytes))
    }

    func testNonContiguousCollectionMatchesArray() {
        let bytes = Array("foobar".utf8)
        let lazyBytes = bytes.lazy.map { $0 }
        XCTAssertEqual(FrameDigest(lazyBytes), FrameDigest(bytes))
    }

    func testRowHashingIgnoresPadding() {
        // Two 2x2 "images" with 3 used bytes per row and different padding bytes.
        let paddedA: [UInt8] = [1, 2, 3, 0xAA, 4, 5, 6, 0xBB]
        let paddedB: [UInt8] = [1, 2, 3, 0x00, 4, 5, 6, 0xFF]
        let packed: [UInt8] = [1, 2, 3, 4, 5, 6]

        func rowDigest(_ bytes: [UInt8]) -> FrameDigest {
            bytes.withUnsafeBytes { FrameDigest(rows: $0, bytesPerRow: 4, rowLength: 3, rowCount: 2) }
        }

        XCTAssertEqual(rowDigest(paddedA), rowDigest(paddedB))
        XCTAssertEqual(rowDigest(paddedA), FrameDigest(packed))
    }

    func testRowHashingDetectsPixelChange() {
        let a: [UInt8] = [1, 2, 3, 0, 4, 5, 6, 0]
        let b: [UInt8] = [1, 2, 3, 0, 4, 5, 7, 0]
        let digestA = a.withUnsafeBytes { FrameDigest(rows: $0, bytesPerRow: 4, rowLength: 3, rowCount: 2) }
        let digestB = b.withUnsafeBytes { FrameDigest(rows: $0, bytesPerRow: 4, rowLength: 3, rowCount: 2) }
        XCTAssertNotEqual(digestA, digestB)
    }

    func testDescriptionIsZeroPaddedHex() {
        XCTAssertEqual(FrameDigest(value: 0xff).description, "00000000000000ff")
    }
}
