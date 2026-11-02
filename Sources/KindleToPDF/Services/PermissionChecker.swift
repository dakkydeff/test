#if os(macOS)
import AppKit
import ApplicationServices
import CoreGraphics

/// Screen Recording / Accessibility permission state and helpers.
@MainActor
final class PermissionChecker: ObservableObject {
    @Published private(set) var screenRecordingGranted = false
    @Published private(set) var accessibilityGranted = false

    init() {
        refresh()
    }

    func refresh() {
        screenRecordingGranted = Self.hasScreenRecordingAccess()
        accessibilityGranted = Self.hasAccessibilityAccess()
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
