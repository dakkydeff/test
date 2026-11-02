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
    case cropLeavesNothing
    case cropFailed

    var errorDescription: String? {
        switch self {
        case .windowNotFound:
            return "対象のウィンドウが見つかりません。Kindle が終了・最小化されていないか確認してください。"
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

    /// On-screen, normal-level windows of other apps, Kindle windows first.
    func availableWindows() async throws -> [CapturableWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownPID = ProcessInfo.processInfo.processIdentifier

        let windows = content.windows.compactMap { window -> CapturableWindow? in
            guard let app = window.owningApplication,
                  app.processID != ownPID,
                  window.windowLayer == 0,
                  window.frame.width >= 100,
                  window.frame.height >= 100
            else { return nil }
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
    func capture(windowID: CGWindowID, cropInsets: CropInsets) async throws -> CGImage {
        // Re-query every time so the window's current size and display are used.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
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
