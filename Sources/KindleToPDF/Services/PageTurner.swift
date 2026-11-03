#if os(macOS)
import AppKit
import ApplicationServices
import CoreGraphics

enum PageTurnError: LocalizedError {
    case accessibilityNotGranted
    case targetNotRunning
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "アクセシビリティが許可されていないため、ページ送りできません。システム設定で KindleToPDF を許可してください。"
        case .targetNotRunning:
            return "Kindle が起動していません。"
        case .eventCreationFailed:
            return "キーイベントを作成できませんでした。"
        }
    }
}

/// Turns pages by sending the right-arrow key directly to the Kindle process.
///
/// The key events are posted to the process (`postToPid`), not to the system
/// event queue, so they reach Kindle even while another app is in front and never
/// land in whatever the user is typing into. With `bringsTargetToFront == false`
/// (background mode) Kindle is therefore left alone; with `true` it is activated
/// before each page turn, for Kindle builds that ignore keys while inactive.
@MainActor
final class PageTurner {
    /// kVK_RightArrow
    static let rightArrowKeyCode: CGKeyCode = 0x7C

    let targetPID: pid_t
    let bringsTargetToFront: Bool

    init(targetPID: pid_t, bringsTargetToFront: Bool) {
        self.targetPID = targetPID
        self.bringsTargetToFront = bringsTargetToFront
    }

    /// Fails early (and shows the system prompt) when Accessibility is not granted.
    func ensureAccessibility() throws {
        guard PermissionChecker.requestAccessibilityAccess() else {
            throw PageTurnError.accessibilityNotGranted
        }
    }

    /// Brings the target app to the front.
    @discardableResult
    func activateTarget() throws -> Bool {
        guard let app = runningTarget() else { throw PageTurnError.targetNotRunning }
        // macOS 14 uses cooperative activation: the active app (us) yields first.
        // NOTE(verify-on-mac): yieldActivation(to:) is macOS 14.0+; activate(options: [])
        // without .activateIgnoringOtherApps relies on that yield.
        NSApp.yieldActivation(to: app)
        return app.activate(options: [])
    }

    /// Sends right-arrow keyDown, waits ~30 ms, then keyUp to the target process.
    func turnPage() async throws {
        guard PermissionChecker.hasAccessibilityAccess() else {
            throw PageTurnError.accessibilityNotGranted
        }
        guard let app = runningTarget() else { throw PageTurnError.targetNotRunning }
        if bringsTargetToFront, !app.isActive {
            try activateTarget()
            try await Task.sleep(for: .milliseconds(300))
        }

        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = makeKeyEvent(source: source, keyDown: true),
              let keyUp = makeKeyEvent(source: source, keyDown: false)
        else { throw PageTurnError.eventCreationFailed }

        keyDown.postToPid(targetPID)
        // Always send keyUp, even if the task is cancelled during the pause.
        try? await Task.sleep(for: .milliseconds(30))
        keyUp.postToPid(targetPID)
    }

    private func makeKeyEvent(source: CGEventSource?, keyDown: Bool) -> CGEvent? {
        let event = CGEvent(keyboardEventSource: source, virtualKey: Self.rightArrowKeyCode, keyDown: keyDown)
        // Hardware arrow-key events carry these flags; setting them explicitly also
        // clears any modifier the user might be holding (e.g. Shift).
        // NOTE(verify-on-mac): if Kindle ignores the key, try removing these flags.
        event?.flags = [.maskNumericPad, .maskSecondaryFn]
        return event
    }

    private func runningTarget() -> NSRunningApplication? {
        guard let app = NSRunningApplication(processIdentifier: targetPID), !app.isTerminated else {
            return nil
        }
        return app
    }
}
#endif
