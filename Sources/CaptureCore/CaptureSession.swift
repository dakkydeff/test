import Foundation

public enum FinishReason: Equatable, Sendable {
    case endOfBook
    case maxPagesReached
    case userStopped
}

public enum CaptureState: Equatable, Sendable {
    case idle
    case running(page: Int)
    case stopping
    case finished(pages: Int, reason: FinishReason)
    case failed(message: String)

    /// True while a run is in progress (including while it is winding down).
    public var isActive: Bool {
        switch self {
        case .running, .stopping:
            return true
        case .idle, .finished, .failed:
            return false
        }
    }
}

/// Pure state machine for one capture run:
/// idle/finished/failed -> running -> (stopping) -> finished | failed.
/// Invalid transitions are ignored and reported via the `Bool` results.
public struct CaptureSession: Equatable, Sendable {
    public private(set) var state: CaptureState

    public init(state: CaptureState = .idle) {
        self.state = state
    }

    public var isActive: Bool { state.isActive }

    /// Begins a new run at page 0. Fails while another run is active.
    @discardableResult
    public mutating func start() -> Bool {
        guard !state.isActive else { return false }
        state = .running(page: 0)
        return true
    }

    /// Records that `page` has been captured. Ignored unless running.
    @discardableResult
    public mutating func recordPage(_ page: Int) -> Bool {
        guard case .running = state else { return false }
        state = .running(page: page)
        return true
    }

    /// The user asked to stop; the runner finishes up asynchronously.
    @discardableResult
    public mutating func requestStop() -> Bool {
        guard case .running = state else { return false }
        state = .stopping
        return true
    }

    @discardableResult
    public mutating func finish(pages: Int, reason: FinishReason) -> Bool {
        guard state.isActive else { return false }
        state = .finished(pages: pages, reason: reason)
        return true
    }

    @discardableResult
    public mutating func fail(_ message: String) -> Bool {
        guard state.isActive else { return false }
        state = .failed(message: message)
        return true
    }
}

/// Number of trailing captured frames to discard when a run ends.
///
/// Ending on `.endOfBook` means the last `stableFramesToStop` frames are the same
/// final page; one copy is kept and the remaining `stableFramesToStop - 1` are
/// dropped. Other reasons keep everything.
public func trailingFramesToDrop(reason: FinishReason, stableFramesToStop: Int) -> Int {
    switch reason {
    case .endOfBook:
        return EndOfBookDetector.effectiveThreshold(stableFramesToStop) - 1
    case .maxPagesReached, .userStopped:
        return 0
    }
}

/// Number of captured frames that should go into the PDF.
public func pagesToKeep(capturedCount: Int, reason: FinishReason, stableFramesToStop: Int) -> Int {
    let drop = trailingFramesToDrop(reason: reason, stableFramesToStop: stableFramesToStop)
    return max(0, capturedCount - drop)
}
