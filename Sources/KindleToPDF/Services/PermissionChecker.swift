#if os(macOS)
import AppKit
import ApplicationServices
import CoreGraphics

/// Screen Recording / Accessibility permission state and helpers.
@MainActor
final class PermissionChecker: ObservableObject {
    @Published private(set) var screenRecordingGranted = false
    @Published private(set) var accessibilityGranted = false

    /// CGPreflightScreenCaptureAccess() reports the value from process launch and
    /// keeps returning false after the user grants access until the app restarts.
    /// A successful window listing proves the capability is actually available,
    /// so once that happens the flag stays true for this process.
    private var screenRecordingProven = false

    init() {
        refresh()
    }

    func refresh() {
        screenRecordingGranted = screenRecordingProven || Self.hasScreenRecordingAccess()
        accessibilityGranted = Self.hasAccessibilityAccess()
    }

    /// Call after ScreenCaptureKit returned window content successfully.
    func markScreenRecordingProven() {
        screenRecordingProven = true
        if !screenRecordingGranted { screenRecordingGranted = true }
    }

    // MARK: Screen Recording

    nonisolated static func hasScreenRecordingAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Shows the system prompt the first time; returns the current state.
    @discardableResult
    nonisolated static func requestScreenRecordingAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    // MARK: Accessibility

    nonisolated static func hasAccessibilityAccess() -> Bool {
        AXIsProcessTrusted()
    }

    /// Returns the current state and, if not trusted, asks the system to show its prompt.
    @discardableResult
    nonisolated static func requestAccessibilityAccess() -> Bool {
        // NOTE(verify-on-mac): kAXTrustedCheckOptionPrompt is imported as Unmanaged<CFString>.
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    // MARK: System Settings

    static func openScreenRecordingSettings() {
        openPrivacyPane("Privacy_ScreenCapture")
    }

    static func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    private static func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
#endif
