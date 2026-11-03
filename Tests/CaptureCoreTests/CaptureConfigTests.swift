import CaptureCore
import XCTest

final class CaptureConfigTests: XCTestCase {
    func testDefaults() {
        let config = CaptureConfig()
        XCTAssertEqual(config.pageInterval, 1.0)
        XCTAssertEqual(config.maxPages, 2000)
        XCTAssertEqual(config.stableFramesToStop, 3)
        XCTAssertEqual(config.cropInsets, .zero)
        XCTAssertFalse(config.bringsKindleToFront, "background mode is the default")
        XCTAssertEqual(config.clamped(), config)
    }

    func testClampingKeepsForegroundFlag() {
        XCTAssertTrue(CaptureConfig(bringsKindleToFront: true).clamped().bringsKindleToFront)
    }

    func testPageIntervalIsClamped() {
        XCTAssertEqual(CaptureConfig(pageInterval: 0.1).clamped().pageInterval, 0.3)
        XCTAssertEqual(CaptureConfig(pageInterval: -5).clamped().pageInterval, 0.3)
        XCTAssertEqual(CaptureConfig(pageInterval: 60).clamped().pageInterval, 10)
        XCTAssertEqual(CaptureConfig(pageInterval: .infinity).clamped().pageInterval, 10)
        XCTAssertEqual(CaptureConfig(pageInterval: .nan).clamped().pageInterval, 1.0)
        XCTAssertEqual(CaptureConfig(pageInterval: 2.5).clamped().pageInterval, 2.5)
    }

    func testMaxPagesIsClamped() {
        XCTAssertEqual(CaptureConfig(maxPages: 0).clamped().maxPages, 1)
        XCTAssertEqual(CaptureConfig(maxPages: -10).clamped().maxPages, 1)
        XCTAssertEqual(CaptureConfig(maxPages: 20_000).clamped().maxPages, 10_000)
        XCTAssertEqual(CaptureConfig(maxPages: 500).clamped().maxPages, 500)
    }

    func testStableFramesIsClamped() {
        XCTAssertEqual(CaptureConfig(stableFramesToStop: 1).clamped().stableFramesToStop, 2)
        XCTAssertEqual(CaptureConfig(stableFramesToStop: 11).clamped().stableFramesToStop, 10)
        XCTAssertEqual(CaptureConfig(stableFramesToStop: 5).clamped().stableFramesToStop, 5)
    }

    func testCropInsetsAreClamped() {
        let insets = CropInsets(top: -1, left: 5, bottom: 1_000_000, right: 0)
        XCTAssertEqual(
            CaptureConfig(cropInsets: insets).clamped().cropInsets,
            CropInsets(top: 0, left: 5, bottom: CropInsets.maxInset, right: 0)
        )
    }

    func testCropRect() {
        let insets = CropInsets(top: 10, left: 20, bottom: 30, right: 40)
        XCTAssertEqual(
            insets.cropRect(imageWidth: 1000, imageHeight: 800),
            PixelRect(x: 20, y: 10, width: 940, height: 760)
        )
        XCTAssertEqual(
            CropInsets.zero.cropRect(imageWidth: 100, imageHeight: 50),
            PixelRect(x: 0, y: 0, width: 100, height: 50)
        )
    }

    func testCropRectIsNilWhenNothingRemains() {
        XCTAssertNil(CropInsets(left: 50, right: 50).cropRect(imageWidth: 100, imageHeight: 100))
        XCTAssertNil(CropInsets(top: 200).cropRect(imageWidth: 100, imageHeight: 100))
    }

    func testIsZero() {
        XCTAssertTrue(CropInsets.zero.isZero)
        XCTAssertFalse(CropInsets(bottom: 1).isZero)
    }
}
