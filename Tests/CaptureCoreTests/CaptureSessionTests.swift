import CaptureCore
import XCTest

final class CaptureSessionTests: XCTestCase {
    func testNormalRun() {
        var session = CaptureSession()
        XCTAssertTrue(session.start())
        XCTAssertEqual(session.state, .running(page: 0))
        XCTAssertTrue(session.recordPage(1))
        XCTAssertEqual(session.state, .running(page: 1))
        XCTAssertTrue(session.finish(pages: 1, reason: .endOfBook))
        XCTAssertEqual(session.state, .finished(pages: 1, reason: .endOfBook))
        XCTAssertFalse(session.isActive)
    }

    func testStopFlow() {
        var session = CaptureSession()
        session.start()
        XCTAssertTrue(session.requestStop())
        XCTAssertEqual(session.state, .stopping)
        XCTAssertTrue(session.isActive)
        XCTAssertFalse(session.recordPage(5), "pages are not recorded while stopping")
        XCTAssertFalse(session.requestStop())
        XCTAssertTrue(session.finish(pages: 4, reason: .userStopped))
        XCTAssertEqual(session.state, .finished(pages: 4, reason: .userStopped))
    }

    func testInvalidTransitionsAreIgnored() {
        var session = CaptureSession()
        XCTAssertFalse(session.requestStop())
        XCTAssertFalse(session.finish(pages: 1, reason: .endOfBook))
        XCTAssertFalse(session.fail("x"))
        XCTAssertEqual(session.state, .idle)

        session.start()
        XCTAssertFalse(session.start(), "cannot start twice")
    }

    func testRestartAfterFailure() {
        var session = CaptureSession()
        session.start()
        session.fail("boom")
        XCTAssertEqual(session.state, .failed(message: "boom"))
        XCTAssertTrue(session.start())
        XCTAssertEqual(session.state, .running(page: 0))
    }
}
