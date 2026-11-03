#if os(macOS)
import AppKit
import CaptureCore
import ScreenCaptureKit

/// A window the user can pick as the capture target (value snapshot of an SCWindow).
struct CapturableWindow: Identifiable, Hashable, Sendable {
    let id: CGWindowID
    let title: String
    let applicationName: String
    let bundleIdentifier: String
    let processID: pid_t
    let size: CGSize

    var isKindle: Bool {
        WindowCapturer.kindleBundleIdentifiers.contains(bundleIdentifier)
    }

    var displayName: String {
        let name = title.isEmpty ? "（無題）" : title
        return "\(applicationName) — \(name)  [\(Int(size.width))×\(Int(size.height))]"
    }
}

enum WindowCaptureError: LocalizedError {
    case windowNotFound
    case captureFailed
    case cropLeavesNothing
    case cropFailed

    var errorDescription: String? {
        switch self {
        case .captureFailed:
            return "ウィンドウの画像を取得できませんでした。Kindle が最小化されていないか確認してください。"
        case .windowNotFound:
            return "対象のウィンドウが見つかりません。Kindle が終了・最小化（Dock にしまう）されていないか確認してください。"
        case .cropLeavesNothing:
            return "トリミング量が画像サイズ以上です。トリミングの値を小さくしてください。"
        case .cropFailed:
            return "画像のトリミングに失敗しました。"
        }
    }
}

/// Lists windows and captures a single window with ScreenCaptureKit.
@MainActor
final class WindowCapturer {
    static let kindleBundleIdentifiers: Set<String> = ["com.amazon.Kindle", "com.amazon.Lassen"]

    /// The SCWindow objects last seen for each window ID. If a fresh query momentarily
    /// omits a window (e.g. during a Space switch), capture falls back to this.
    private var knownWindows: [CGWindowID: SCWindow] = [:]

    /// Which API produced the frames of the current run. ScreenCaptureKit is tried
    /// first; it cannot capture a window that sits on another Space ("failed to
    /// start stream"), so on failure the run switches to the window-server image
    /// API and stays there, keeping the pixel format identical between frames.
    enum Backend: String {
        case screenCaptureKit = "ScreenCaptureKit"
        case windowServer = "CGWindowListCreateImage"
    }
    private(set) var backend: Backend = .screenCaptureKit
    /// Called once when the backend switches, for the run log.
    var onBackendChange: ((Backend) -> Void)?

    /// Resets the backend choice for a new run.
    func beginRun() {
        backend = .screenCaptureKit
    }

    /// Normal-level windows of other apps, Kindle windows first. Kindle windows are
    /// listed even when they are on another Space; other apps only when on screen.
    func availableWindows() async throws -> [CapturableWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let ownPID = ProcessInfo.processInfo.processIdentifier

        let windows = content.windows.compactMap { window -> CapturableWindow? in
            guard let app = window.owningApplication,
                  app.processID != ownPID,
                  window.windowLayer == 0,
                  window.frame.width >= 100,
                  window.frame.height >= 100,
                  window.isOnScreen || Self.kindleBundleIdentifiers.contains(app.bundleIdentifier)
            else { return nil }
            knownWindows[window.windowID] = window
            return CapturableWindow(
                id: window.windowID,
                title: window.title ?? "",
                applicationName: app.applicationName,
                bundleIdentifier: app.bundleIdentifier,
                processID: app.processID,
                size: window.frame.size
            )
        }

        return windows.sorted { lhs, rhs in
            if lhs.isKindle != rhs.isKindle { return lhs.isKindle }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    /// Captures one frame of the window at full backing resolution, then applies `cropInsets`.
    ///
    /// The window does not have to be visible: `desktopIndependentWindow` captures from the
    /// window's own backing store, so it may be covered by other windows or sit on another
    /// Space. A minimized window cannot be captured.
    func capture(windowID: CGWindowID, cropInsets: CropInsets) async throws -> CGImage {
        if backend == .windowServer {
            return try Self.crop(try Self.captureViaWindowServer(windowID: windowID), insets: cropInsets)
        }
        do {
            return try await captureViaScreenCaptureKit(windowID: windowID, cropInsets: cropInsets)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Typical failure: the window is on another Space. Fall back for the rest of the run.
            let image = try Self.captureViaWindowServer(windowID: windowID)
            backend = .windowServer
            onBackendChange?(.windowServer)
            return try Self.crop(image, insets: cropInsets)
        }
    }

    /// Captures the window's current contents straight from the window server. Works
    /// for windows behind other windows and on other Spaces, but not minimized ones.
    /// Deprecated since macOS 14 in favour of ScreenCaptureKit, yet still functional,
    /// and ScreenCaptureKit has no equivalent for off-Space windows.
    // NOTE(verify-on-mac): expect a deprecation warning here, not an error. A window
    // that cannot be captured yields nil or a 1x1 image, both treated as failure.
    static func captureViaWindowServer(windowID: CGWindowID) throws -> CGImage {
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ), image.width > 1, image.height > 1 else {
            throw WindowCaptureError.captureFailed
        }
        return image
    }

    private func captureViaScreenCaptureKit(windowID: CGWindowID, cropInsets: CropInsets) async throws -> CGImage {
        // Re-query every time so the window's current size and display are used.
        // NOTE(verify-on-mac): onScreenWindowsOnly: false is what makes windows on other
        // Spaces show up; confirm SCScreenshotManager returns their current content.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        if let fresh = content.windows.first(where: { $0.windowID == windowID }) {
            knownWindows[windowID] = fresh
        }
        guard let window = knownWindows[windowID] else {
            throw WindowCaptureError.windowNotFound
        }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = backingScale(of: filter)

        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((window.frame.width * scale).rounded()))
        configuration.height = max(1, Int((window.frame.height * scale).rounded()))
        configuration.showsCursor = false
        // NOTE(verify-on-mac): the three shadow properties below are macOS 14.0+.
        configuration.capturesShadowsOnly = false
        configuration.ignoreShadowsDisplay = true
        configuration.ignoreShadowsSingleWindow = true

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return try Self.crop(image, insets: cropInsets)
    }

    /// Backing scale factor (points -> pixels) of the display showing the window.
    private func backingScale(of filter: SCContentFilter) -> CGFloat {
        // NOTE(verify-on-mac): SCContentFilter.pointPixelScale is macOS 14.0+.
        let scale = CGFloat(filter.pointPixelScale)
        if scale > 0 { return scale }
        return NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
    }

    /// Trims `insets` (in image pixels) from `image`.
    static func crop(_ image: CGImage, insets: CropInsets) throws -> CGImage {
        guard !insets.isZero else { return image }
        guard let rect = insets.cropRect(imageWidth: image.width, imageHeight: image.height) else {
            throw WindowCaptureError.cropLeavesNothing
        }
        // NOTE(verify-on-mac): cropping(to:) works on the pixel grid with y = 0 at the top row.
        let cgRect = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
        guard let cropped = image.cropping(to: cgRect) else {
            throw WindowCaptureError.cropFailed
        }
        // A cropped CGImage may share the parent's backing store, so its dataProvider
        // could expose uncropped bytes. Redraw into a fresh bitmap so FrameDigest only
        // sees the cropped pixels.
        return materialize(cropped) ?? cropped
    }

    private static func materialize(_ image: CGImage) -> CGImage? {
        let colorSpace: CGColorSpace
        if let own = image.colorSpace, own.model == .rgb {
            colorSpace = own
        } else {
            colorSpace = CGColorSpaceCreateDeviceRGB()
        }
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}
#endif
