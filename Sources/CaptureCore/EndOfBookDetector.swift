import Foundation

public enum EndOfBookDecision: Equatable, Sendable {
    case `continue`
    case endOfBook
}

/// Detects the end of a book: once page turns stop changing the window,
/// the same frame is captured over and over.
///
/// `consecutiveIdenticalCount` is the length of the current run of identical
/// frames, including the first frame of the run. The very first frame has
/// nothing to compare against and simply starts a run of 1. When the run
/// reaches `stableFramesToStop`, `observe(_:)` returns `.endOfBook`.
///
/// Example with `stableFramesToStop == 3`: A, B, A, A, A -> `.endOfBook` on the 5th frame.
public struct EndOfBookDetector: Sendable {
    /// Smallest meaningful threshold; 1 would end on the very first frame.
    public static let minimumStableFrames = 2

    /// Normalises a user-supplied threshold to at least `minimumStableFrames`.
    public static func effectiveThreshold(_ stableFramesToStop: Int) -> Int {
        max(minimumStableFrames, stableFramesToStop)
    }

    public let stableFramesToStop: Int
    public private(set) var consecutiveIdenticalCount: Int = 0
    private var previous: FrameDigest?

    public init(stableFramesToStop: Int) {
        self.stableFramesToStop = Self.effectiveThreshold(stableFramesToStop)
    }

    /// Feeds the digest of the frame captured after the latest page turn.
    /// An identical digest extends the current run; a different one starts a new run.
    public mutating func observe(_ digest: FrameDigest) -> EndOfBookDecision {
        if let previous, previous == digest {
            consecutiveIdenticalCount += 1
        } else {
            consecutiveIdenticalCount = 1
        }
        previous = digest
        return consecutiveIdenticalCount >= stableFramesToStop ? .endOfBook : .continue
    }

    /// Forgets all observed frames.
    public mutating func reset() {
        previous = nil
        consecutiveIdenticalCount = 0
    }
}
