#if os(macOS)
import AppKit
import CaptureCore
import SwiftUI
import UniformTypeIdentifiers

/// Main screen: permissions, window picker, settings, output, controls, progress.
@MainActor
struct ContentView: View {
    @StateObject private var permissions = PermissionChecker()
    @StateObject private var runner = CaptureRunner()

    @State private var windows: [CapturableWindow] = []
    @State private var selectedWindowID: CGWindowID?
    @State private var windowListError: String?
    @State private var config = CaptureConfig()
    @State private var outputURL: URL?
    @State private var title = ""
    /// The last title filled in automatically from the window name.
    @State private var autoFilledTitle = ""

    private let capturer = WindowCapturer()

    private var selectedWindow: CapturableWindow? {
        windows.first { $0.id == selectedWindowID }
    }

    private var canStart: Bool {
        !runner.isRunning
            && selectedWindow != nil
            && permissions.screenRecordingGranted
            && permissions.accessibilityGranted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PermissionsView(permissions: permissions)

            WindowPickerView(
                windows: windows,
                selection: $selectedWindowID,
                errorMessage: windowListError,
                onRefresh: { Task { await reloadWindows() } }
            )
            .disabled(runner.isRunning)

            settingsSection
            outputSection
            controlSection

            CaptureProgressView(runner: runner)

            notice
        }
        .padding(20)
        .task { await reloadWindows() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
        .onChange(of: selectedWindowID) { _, _ in
            updateAutoTitle()
        }
        .alert(
            "撮影を中断しました",
            isPresented: Binding(get: { runner.partialSavePrompt != nil }, set: { _ in }),
            presenting: runner.partialSavePrompt
        ) { _ in
            Button("PDF を保存") { runner.resolvePartialSave(true) }
            Button("破棄", role: .destructive) { runner.resolvePartialSave(false) }
        } message: { pages in
            Text("ここまでに撮影した \(pages) ページで PDF を保存しますか？")
        }
    }

    // MARK: - Sections

    private var settingsSection: some View {
        GroupBox("設定") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("ページ送り間隔")
                    Stepper(value: $config.pageInterval, in: CaptureConfig.pageIntervalRange, step: 0.1) {
                        Text(String(format: "%.1f 秒", config.pageInterval))
                            .monospacedDigit()
                    }
                }
                GridRow {
                    Text("最大ページ数")
                    TextField("最大ページ数", value: $config.maxPages, format: .number)
                        .frame(width: 100)
                }
                GridRow {
                    Text("終了判定")
                    Stepper(value: $config.stableFramesToStop, in: CaptureConfig.stableFramesRange) {
                        Text("同じ画面が \(config.stableFramesToStop) 回続いたら終了")
                    }
                }
                GridRow {
                    Text("トリミング (px)")
                    HStack(spacing: 10) {
                        insetField("上", \.top)
                        insetField("左", \.left)
                        insetField("下", \.bottom)
                        insetField("右", \.right)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(runner.isRunning)
    }

    private var outputSection: some View {
        GroupBox("出力") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("タイトル")
                    TextField("PDF のタイトル（既定は Kindle のウィンドウ名）", text: $title)
                }
                GridRow {
                    Text("保存先")
                    HStack {
                        Text(outputURL?.path ?? "未指定（デスクトップに保存します）")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(outputURL == nil ? HierarchicalShapeStyle.secondary : HierarchicalShapeStyle.primary)
                        Spacer()
                        Button("選択…", action: chooseOutputLocation)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(runner.isRunning)
    }

    private var controlSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("開始", action: startCapture)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canStart)
                Button("停止") { runner.stop() }
                    .disabled(!isRunningState)
                Spacer()
                if let url = runner.lastOutputURL, !runner.isRunning {
                    Button("Finder で表示") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            }
            Text("開始する前に、Kindle で本の最初のページを表示しておいてください。撮影中に KindleToPDF のウィンドウをクリックすると一時停止します。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var notice: some View {
        Text("個人利用のみ。著作権法上の私的複製の範囲内でご利用ください。本アプリは DRM の解除を行わず、画面に表示された内容をキャプチャするだけです。")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// True only while pages are still being captured; stopping is not offered
    /// twice, nor once the PDF is being written.
    private var isRunningState: Bool {
        if case .running = runner.state { return !runner.isBuildingPDF }
        return false
    }

    private func insetField(_ label: String, _ keyPath: WritableKeyPath<CropInsets, Int>) -> some View {
        HStack(spacing: 4) {
            Text(label)
            TextField(
                label,
                value: Binding(
                    get: { config.cropInsets[keyPath: keyPath] },
                    set: { config.cropInsets[keyPath: keyPath] = max(0, $0) }
                ),
                format: .number
            )
            .frame(width: 56)
        }
    }

    // MARK: - Actions

    private func reloadWindows() async {
        do {
            windows = try await capturer.availableWindows()
            windowListError = nil
            if selectedWindow == nil {
                selectedWindowID = windows.first(where: \.isKindle)?.id
            }
        } catch {
            windows = []
            windowListError = "ウィンドウ一覧を取得できません（画面収録の許可を確認してください）: \(error.localizedDescription)"
        }
        permissions.refresh()
    }

    private func updateAutoTitle() {
        guard let window = selectedWindow else { return }
        // Only replace the title if the user has not typed their own.
        if title.isEmpty || title == autoFilledTitle {
            title = window.title
            autoFilledTitle = window.title
        }
    }

    private func chooseOutputLocation() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = Self.sanitizedFileName(effectiveTitle) + ".pdf"
        if panel.runModal() == .OK, let url = panel.url {
            outputURL = url
        }
    }

    private func startCapture() {
        guard let window = selectedWindow else { return }
        config = config.clamped()
        let job = CaptureJob(
            window: window,
            config: config,
            outputURL: resolvedOutputURL(),
            title: effectiveTitle
        )
        runner.start(job)
    }

    // MARK: - Output naming

    private var effectiveTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let windowTitle = selectedWindow?.title, !windowTitle.isEmpty { return windowTitle }
        return "Kindle"
    }

    /// The chosen URL, or a non-existing file on the Desktop named after the title.
    private func resolvedOutputURL() -> URL {
        if let outputURL { return outputURL }
        let fileManager = FileManager.default
        let directory = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
        let baseName = Self.sanitizedFileName(effectiveTitle)
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension("pdf")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(suffix)").appendingPathExtension("pdf")
            suffix += 1
        }
        return candidate
    }

    private static func sanitizedFileName(_ title: String) -> String {
        let cleaned = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = String(cleaned.prefix(100))
        return name.isEmpty ? "KindleToPDF" : name
    }
}
#endif
