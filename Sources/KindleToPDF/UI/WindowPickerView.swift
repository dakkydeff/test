#if os(macOS)
import CoreGraphics
import SwiftUI

/// Picker for the capture target. Kindle windows are listed first; other
/// windows are hidden behind a checkbox (for differently named Kindle builds).
struct WindowPickerView: View {
    let windows: [CapturableWindow]
    @Binding var selection: CGWindowID?
    let errorMessage: String?
    let onRefresh: () -> Void

    @State private var showsOtherWindows = false

    private var kindleWindows: [CapturableWindow] { windows.filter(\.isKindle) }
    private var otherWindows: [CapturableWindow] { windows.filter { !$0.isKindle } }

    private var selectionIsOtherWindow: Bool {
        otherWindows.contains { $0.id == selection }
    }

    var body: some View {
        GroupBox("キャプチャするウィンドウ") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Picker("ウィンドウ", selection: $selection) {
                        Text("選択してください").tag(CGWindowID?.none)
                        if !kindleWindows.isEmpty {
                            Section("Kindle") {
                                ForEach(kindleWindows) { window in
                                    Text(window.displayName).tag(Optional(window.id))
                                }
                            }
                        }
                        if (showsOtherWindows || selectionIsOtherWindow) && !otherWindows.isEmpty {
                            Section("その他のウィンドウ") {
                                ForEach(otherWindows) { window in
                                    Text(window.displayName).tag(Optional(window.id))
                                }
                            }
                        }
                    }
                    .labelsHidden()

                    Button(action: onRefresh) {
                        Label("更新", systemImage: "arrow.clockwise")
                    }
                }

                Toggle("Kindle 以外のウィンドウも表示する", isOn: $showsOtherWindows)
                    .toggleStyle(.checkbox)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if kindleWindows.isEmpty {
                    Text("Kindle のウィンドウが見つかりません。Kindle for Mac で本を開いてから「更新」を押してください。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif
