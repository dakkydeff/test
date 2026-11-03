import Foundation

/// A rectangle in pixel coordinates with the origin at the top-left of the image.
public struct PixelRect: Equatable, Hashable, Sendable {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Margins trimmed from every captured frame, in pixels of the captured image
/// (i.e. already multiplied by the display's backing scale).
public struct CropInsets: Equatable, Hashable, Sendable {
    /// Upper bound for a single inset; keeps arithmetic far away from overflow.
    public static let maxInset = 100_000

    public var top: Int
    public var left: Int
    public var bottom: Int
    public var right: Int

    public static let zero = CropInsets()

    public init(top: Int = 0, left: Int = 0, bottom: Int = 0, right: Int = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public var isZero: Bool {
        top == 0 && left == 0 && bottom == 0 && right == 0
    }

    /// Returns a copy with every inset limited to `0...maxInset`.
    public func clamped() -> CropInsets {
        let range = 0...Self.maxInset
        return CropInsets(
            top: top.clamped(to: range),
            left: left.clamped(to: range),
            bottom: bottom.clamped(to: range),
            right: right.clamped(to: range)
        )
    }

    /// The region that remains after trimming an image of the given pixel size,
    /// or `nil` when the insets would leave nothing.
    public func cropRect(imageWidth: Int, imageHeight: Int) -> PixelRect? {
        let insets = clamped()
        let width = imageWidth - insets.left - insets.right
        let height = imageHeight - insets.top - insets.bottom
        guard width > 0, height > 0 else { return nil }
        return PixelRect(x: insets.left, y: insets.top, width: width, height: height)
    }
}

/// User-tunable settings for one capture run.
public struct CaptureConfig: Equatable, Sendable {
    public static let pageIntervalRange: ClosedRange<TimeInterval> = 0.3...10
    public static let maxPagesRange: ClosedRange<Int> = 1...10_000
    public static let stableFramesRange: ClosedRange<Int> = 2...10

    public static let defaultPageInterval: TimeInterval = 1.0
    public static let defaultMaxPages = 2000
    public static let defaultStableFramesToStop = 3

    /// Seconds to wait after each page turn before the next capture (0.3 ... 10).
    public var pageInterval: TimeInterval = CaptureConfig.defaultPageInterval
    /// Hard upper bound on captured pages (1 ... 10000).
    public var maxPages: Int = CaptureConfig.defaultMaxPages
    /// Number of identical consecutive frames that signals the end of the book (2 ... 10).
    public var stableFramesToStop: Int = CaptureConfig.defaultStableFramesToStop
    /// Pixels trimmed from each frame (top/left/bottom/right).
    public var cropInsets: CropInsets = .zero
    /// `false` (background mode, the default): Kindle is never activated; page-turn
    /// keys are posted straight to its process and the window is captured even when
    /// it is hidden behind other windows or on another Space, so the Mac stays usable.
    /// `true` (foreground mode): Kindle is brought to the front before each page turn,
    /// for builds of Kindle that ignore key events while inactive.
    public var bringsKindleToFront: Bool = false

    public init(
        pageInterval: TimeInterval = CaptureConfig.defaultPageInterval,
        maxPages: Int = CaptureConfig.defaultMaxPages,
        stableFramesToStop: Int = CaptureConfig.defaultStableFramesToStop,
        cropInsets: CropInsets = .zero,
        bringsKindleToFront: Bool = false
    ) {
        self.pageInterval = pageInterval
        self.maxPages = maxPages
        self.stableFramesToStop = stableFramesToStop
        self.cropInsets = cropInsets
        self.bringsKindleToFront = bringsKindleToFront
    }

    /// Returns a copy with every value forced into its valid range.
    /// A non-finite (NaN) interval falls back to the default.
    public func clamped() -> CaptureConfig {
        let interval = pageInterval.isNaN ? Self.defaultPageInterval : pageInterval
        return CaptureConfig(
            pageInterval: interval.clamped(to: Self.pageIntervalRange),
            maxPages: maxPages.clamped(to: Self.maxPagesRange),
            stableFramesToStop: stableFramesToStop.clamped(to: Self.stableFramesRange),
            cropInsets: cropInsets.clamped(),
            bringsKindleToFront: bringsKindleToFront
        )
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
