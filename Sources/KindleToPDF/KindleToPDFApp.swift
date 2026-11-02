#if os(macOS)
import AppKit
import SwiftUI

@main
struct KindleToPDFApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A single window: one capture runner per app.
        Window("KindleToPDF", id: "main") {
            ContentView()
                .frame(minWidth: 760, minHeight: 760)
        }
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (e.g. `swift run`) rather than from the .app.
        NSApp.setActivationPolicy(.regular)
        // NOTE(verify-on-mac): NSApplication.activate() (no arguments) is macOS 14.0+.
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
#endif
