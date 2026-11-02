import CaptureCore
import XCTest

final class TrailingDuplicateTests: XCTestCase {
    func testEndOfBookDropsAllButOneDuplicate() {
        XCTAssertEqual(trailingFramesToDrop(reason: .endOfBook, stableFramesToStop: 3), 2)
        XCTAssertEqual(trailingFramesToDrop(reason: .endOfBook, stableFramesToStop: 2), 1)
        XCTAssertEqual(trailingFramesToDrop(reason: .endOfBook, stableFramesToStop: 10), 9)
    }

    func testOtherReasonsDropNothing() {
        XCTAssertEqual(trailingFramesToDrop(reason: .maxPagesReached, stableFramesToStop: 3), 0)
        XCTAssertEqual(trailingFramesToDrop(reason: .userStopped, stableFramesToStop: 3), 0)
    }

    func testThresholdIsNormalisedLikeDetector() {
        // The detector treats 1 as 2, so a run of 2 ended the book and 1 frame must go.
        XCTAssertEqual(trailingFramesToDrop(reason: .endOfBook, stableFramesToStop: 1), 1)
    }

    func testPagesToKeep() {
        XCTAssertEqual(pagesToKeep(capturedCount: 10, reason: .endOfBook, stableFramesToStop: 3), 8)
        XCTAssertEqual(pagesToKeep(capturedCount: 10, reason: .maxPagesReached, stableFramesToStop: 3), 10)
        XCTAssertEqual(pagesToKeep(capturedCount: 10, reason: .userStopped, stableFramesToStop: 3), 10)
        XCTAssertEqual(pagesToKeep(capturedCount: 1, reason: .endOfBook, stableFramesToStop: 3), 0)
    }

    /// Simulates a full run: pages A, B, C, then C repeats until the detector fires.
    func testSimulatedRunKeepsEachPageOnce() {
        let pages = ["A", "B", "C", "C", "C"].map { FrameDigest(Array($0.utf8)) }
        let threshold = 3
        var detector = EndOfBookDetector(stableFramesToStop: threshold)
        var captured: [FrameDigest] = []
        var reason: FinishReason = .maxPagesReached

        for page in pages {
            captured.append(page)
            if detector.observe(page) == .endOfBook {
                reason = .endOfBook
                break
            }
        }

        let kept = captured.prefix(pagesToKeep(capturedCount: captured.count, reason: reason, stableFramesToStop: threshold))
        XCTAssertEqual(reason, .endOfBook)
        XCTAssertEqual(Array(kept), Array(pages.prefix(3)))
    }
}
