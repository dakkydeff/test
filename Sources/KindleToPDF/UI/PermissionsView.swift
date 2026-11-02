#if os(macOS)
import SwiftUI

/// Shows the two required permissions with a shortcut to System Settings.
struct PermissionsView: View {
    @ObservedObject var permissions: PermissionChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 24) {
                PermissionStatusRow(
                    title: "画面収録",
                    granted: permissions.screenRecordingGranted
                ) {
                    PermissionChecker.requestScreenRecordingAccess()
                    PermissionChecker.openScreenRecordingSettings()
                }
                PermissionStatusRow(
                    title: "アクセシビリティ",
                    granted: permissions.accessibilityGranted
                ) {
                    PermissionChecker.requestAccessibilityAccess()
                    PermissionChecker.openAccessibilitySettings()
                }
                Spacer()
                Button {
                    permissions.refresh()
                } label: {
                    Label("再確認", systemImage: "arrow.clockwise")
                }
            }
            if !permissions.screenRecordingGranted || !permissions.accessibilityGranted {
                Text("許可した後も反映されない場合は、KindleToPDF を終了して起動し直してください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PermissionStatusRow: View {
    let title: String
    let granted: Bool
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? Color.green : Color.red)
            Text(title)
            if !granted {
                Button("システム設定を開く", action: openSettings)
            }
        }
    }
}
#endif
