import CaptureCore
import XCTest

final class EndOfBookDetectorTests: XCTestCase {
    private let a = FrameDigest(Array("page-a".utf8))
    private let b = FrameDigest(Array("page-b".utf8))

    /// Feeds `frames` and returns the 1-based index of the first `.endOfBook`, or nil.
    private func endIndex(_ frames: [FrameDigest], stableFramesToStop: Int) -> Int? {
        var detector = EndOfBookDetector(stableFramesToStop: stableFramesToStop)
        for (index, frame) in frames.enumerated() {
            if detector.observe(frame) == .endOfBook {
                return index + 1
            }
        }
        return nil
    }

    func testThreeIdenticalFramesEndOnThird() {
        XCTAssertEqual(endIndex([a, a, a], stableFramesToStop: 3), 3)
    }

    func testRunResetsAfterDifferentFrame() {
        XCTAssertEqual(endIndex([a, b, a, a, a], stableFramesToStop: 3), 5)
    }

    func testRunOfSecondFrameEndsOnFifth() {
        XCTAssertEqual(endIndex([a, a, b, b, b], stableFramesToStop: 3), 5)
    }

    func testTwoIdenticalAreNotEnoughForThree() {
        XCTAssertNil(endIndex([a, a, b, b, a], stableFramesToStop: 3))
    }

    func testBoundaryTwo() {
        XCTAssertEqual(endIndex([a, a], stableFramesToStop: 2), 2)
        XCTAssertEqual(endIndex([a, b, b], stableFramesToStop: 2), 3)
        XCTAssertNil(endIndex([a, b, a, b], stableFramesToStop: 2))
    }

    func testFirstFrameNeverEnds() {
        var detector = EndOfBookDetector(stableFramesToStop: 2)
        XCTAssertEqual(detector.observe(a), .continue)
        XCTAssertEqual(detector.consecutiveIdenticalCount, 1)
    }

    func testConsecutiveCountTracksRunLength() {
        var detector = EndOfBookDetector(stableFramesToStop: 5)
        XCTAssertEqual(detector.consecutiveIdenticalCount, 0)
        _ = detector.observe(a)
        _ = detector.observe(a)
        XCTAssertEqual(detector.consecutiveIdenticalCount, 2)
        _ = detector.observe(b)
        XCTAssertEqual(detector.consecutiveIdenticalCount, 1)
    }

    func testThresholdBelowTwoIsRaisedToTwo() {
        XCTAssertEqual(EndOfBookDetector(stableFramesToStop: 1).stableFramesToStop, 2)
        XCTAssertEqual(EndOfBookDetector(stableFramesToStop: 0).stableFramesToStop, 2)
        XCTAssertEqual(endIndex([a, a], stableFramesToStop: 1), 2)
    }

    func testResetForgetsPreviousFrame() {
        var detector = EndOfBookDetector(stableFramesToStop: 2)
        _ = detector.observe(a)
        detector.reset()
        XCTAssertEqual(detector.consecutiveIdenticalCount, 0)
        XCTAssertEqual(detector.observe(a), .continue)
    }
}
