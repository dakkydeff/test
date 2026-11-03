#if os(macOS)
import AppKit
import CaptureCore
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Everything one capture run needs, fixed when the run starts.
struct CaptureJob {
    var window: CapturableWindow
    var config: CaptureConfig
    var outputURL: URL
    var title: String
}

enum CaptureRunnerError: LocalizedError {
    case screenRecordingNotGranted
    case noPages
    case cannotWriteImage(URL)

    var errorDescription: String? {
        switch self {
        case .screenRecordingNotGranted:
            return "画面収録が許可されていません。システム設定で KindleToPDF を許可してください。"
        case .noPages:
            return "撮影できたページがありません。"
        case .cannotWriteImage(let url):
            return "画像を書き出せませんでした: \(url.path)"
        }
    }
}

/// Runs the capture loop: capture -> compare -> turn page -> wait, then builds the PDF.
@MainActor
final class CaptureRunner: ObservableObject {
    @Published private(set) var state: CaptureState = .idle
    @Published private(set) var pageCount = 0
    @Published private(set) var lastThumbnail: NSImage?
    @Published private(set) var log: [String] = []
    @Published private(set) var lastOutputURL: URL?
    /// Non-nil while the run waits for the user to decide whether to save a
    /// partial PDF after stopping; the value is the number of pages captured.
    @Published private(set) var partialSavePrompt: Int?
    /// True while the PDF is being written; stopping is no longer possible at that point.
    @Published private(set) var isBuildingPDF = false

    private static let maxLogLines = 1000
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var session = CaptureSession()
    private var task: Task<Void, Never>?
    private var partialSaveContinuation: CheckedContinuation<Bool, Never>?
    private let capturer = WindowCapturer()

    var isRunning: Bool { state.isActive }

    func start(_ job: CaptureJob) {
        guard task == nil, session.start() else { return }
        state = session.state
        pageCount = 0
        lastThumbnail = nil
        lastOutputURL = nil
        isBuildingPDF = false
        log.removeAll()
        task = Task { [weak self] in
            await self?.run(job)
        }
    }

    /// Stops after the current step; the run then offers to save what it has.
    func stop() {
        // Once capturing is over and the PDF is being written there is nothing to interrupt.
        guard !isBuildingPDF, session.requestStop() else { return }
        state = session.state
        appendLog("停止しています…")
        task?.cancel()
    }

    /// Answers `partialSavePrompt`.
    func resolvePartialSave(_ save: Bool) {
        let continuation = partialSaveContinuation
        partialSaveContinuation = nil
        partialSavePrompt = nil
        continuation?.resume(returning: save)
    }

    // MARK: - Run

    private func run(_ job: CaptureJob) async {
        defer { task = nil }
        let config = job.config.clamped()
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KindleToPDF-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
            appendLog("開始: \(job.window.displayName)")
            let (captured, reason) = try await capturePages(job: job, config: config, workDirectory: workDirectory)
            try await finish(job: job, config: config, captured: captured, reason: reason, workDirectory: workDirectory)
        } catch {
            appendLog("エラー: \(error.localizedDescription)")
            appendLog("撮影済みの画像は次のフォルダに残っています: \(workDirectory.path)")
            session.fail(error.localizedDescription)
            state = session.state
        }
    }

    /// The capture loop. Returns the PNG files written (in page order) and why it ended.
    private func capturePages(
        job: CaptureJob,
        config: CaptureConfig,
        workDirectory: URL
    ) async throws -> ([URL], FinishReason) {
        guard PermissionChecker.hasScreenRecordingAccess() else {
            throw CaptureRunnerError.screenRecordingNotGranted
        }
        let turner = PageTurner(targetPID: job.window.processID, bringsTargetToFront: config.bringsKindleToFront)
        try turner.ensureAccessibility()

        var captured: [URL] = []
        do {
            if config.bringsKindleToFront {
                let activated = try turner.activateTarget()
                if !activated {
                    appendLog("Kindle を前面にできませんでした。Kindle のウィンドウをクリックしてください。")
                }
                try await Task.sleep(for: .milliseconds(500))
            } else {
                appendLog("バックグラウンドモード: Kindle を前面に出さずに撮影します。他の作業をしていて構いません（Kindle を最小化しないでください）。")
            }

            var detector = EndOfBookDetector(stableFramesToStop: config.stableFramesToStop)
            for page in 1...config.maxPages {
                try Task.checkCancellation()

                let image = try await capturer.capture(windowID: job.window.id, cropInsets: config.cropInsets)
                let url = workDirectory.appendingPathComponent(String(format: "page-%05d.png", page))
                let digest = try await Self.persist(image, to: url)
                captured.append(url)

                // Page 1 is observed too: the detector itself treats the first frame as
                // "nothing to compare with" (it can never end the book), and including it
                // keeps the run length equal to the number of identical PNGs on disk, which
                // is what trailingFramesToDrop assumes.
                if detector.observe(digest) == .endOfBook {
                    appendLog("同じ画面が \(config.stableFramesToStop) 回続いたため、本の終わりと判断しました。")
                    return (captured, .endOfBook)
                }

                pageCount = page
                session.recordPage(page)
                state = session.state
                lastThumbnail = NSImage(cgImage: image, size: .zero)

                if page == config.maxPages { break }

                if config.bringsKindleToFront {
                    try await waitWhileOwnAppIsFrontmost()
                }
                try await turner.turnPage()
                try await Task.sleep(for: .seconds(config.pageInterval))
            }
            appendLog("最大ページ数 (\(config.maxPages)) に達しました。")
            return (captured, .maxPagesReached)
        } catch is CancellationError {
            return (captured, .userStopped)
        }
    }

    /// Drops trailing duplicates, asks about partial saves, builds the PDF and cleans up.
    private func finish(
        job: CaptureJob,
        config: CaptureConfig,
        captured: [URL],
        reason: FinishReason,
        workDirectory: URL
    ) async throws {
        let keepCount = pagesToKeep(
            capturedCount: captured.count,
            reason: reason,
            stableFramesToStop: config.stableFramesToStop
        )
        if captured.count > keepCount {
            appendLog("末尾の重複ページ \(captured.count - keepCount) 枚を除外しました。")
        }
        let pages = Array(captured.prefix(keepCount))
        pageCount = pages.count

        if reason == .userStopped {
            appendLog("停止しました（\(pages.count) ページ撮影済み）。")
            var shouldSave = false
            if !pages.isEmpty {
                shouldSave = await askToSavePartial(pageCount: pages.count)
            }
            guard shouldSave else {
                removeDirectory(workDirectory)
                appendLog("PDF は保存しませんでした。")
                complete(pages: 0, reason: reason)
                return
            }
        }

        guard !pages.isEmpty else { throw CaptureRunnerError.noPages }

        appendLog("PDF を作成しています…（\(pages.count) ページ）")
        isBuildingPDF = true
        defer { isBuildingPDF = false }
        let outputURL = job.outputURL
        let title = job.title
        try await Task.detached(priority: .userInitiated) {
            try PDFBuilder.build(imageURLs: pages, outputURL: outputURL, title: title)
        }.value

        lastOutputURL = outputURL
        appendLog("保存しました: \(outputURL.path)")
        removeDirectory(workDirectory)
        complete(pages: pages.count, reason: reason)
    }

    private func complete(pages: Int, reason: FinishReason) {
        session.finish(pages: pages, reason: reason)
        state = session.state
    }

    private func askToSavePartial(pageCount: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            partialSaveContinuation = continuation
            partialSavePrompt = pageCount
        }
    }

    /// Foreground mode only: re-activating Kindle while the user is working in this
    /// window would make the Stop button unreachable, so pause until the user leaves.
    private func waitWhileOwnAppIsFrontmost() async throws {
        guard NSApp.isActive else { return }
        appendLog("KindleToPDF が前面にあるため一時停止中です。Kindle のウィンドウをクリックすると再開します。")
        while NSApp.isActive {
            try await Task.sleep(for: .milliseconds(200))
        }
        appendLog("再開します。")
        try await Task.sleep(for: .milliseconds(300))
    }

    /// Writes `image` as PNG and computes its digest off the main actor.
    nonisolated private static func persist(_ image: CGImage, to url: URL) async throws -> FrameDigest {
        try await Task.detached(priority: .userInitiated) {
            try ImageFiles.writePNG(image, to: url)
            if let digest = FrameDigest(image: image) {
                return digest
            }
            // Fallback: PNG encoding is deterministic, so hashing the file works too.
            return FrameDigest(try Data(contentsOf: url))
        }.value
    }

    private func removeDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func appendLog(_ message: String) {
        log.append("[\(Self.timestampFormatter.string(from: Date()))] \(message)")
        if log.count > Self.maxLogLines {
            log.removeFirst(log.count - Self.maxLogLines)
        }
    }
}

// MARK: - Image helpers

enum ImageFiles {
    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else { throw CaptureRunnerError.cannotWriteImage(url) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CaptureRunnerError.cannotWriteImage(url)
        }
    }
}

extension FrameDigest {
    /// Digest of the image's raw pixel bytes (`dataProvider.data`), ignoring row padding.
    init?(image: CGImage) {
        guard let data = image.dataProvider?.data else { return nil }
        let rowLength = image.width * image.bitsPerPixel / 8
        // Keep `data` alive while its bytes are being read.
        let digest: FrameDigest? = withExtendedLifetime(data) {
            guard let pointer = CFDataGetBytePtr(data) else { return nil }
            let buffer = UnsafeRawBufferPointer(start: pointer, count: CFDataGetLength(data))
            return FrameDigest(rows: buffer, bytesPerRow: image.bytesPerRow, rowLength: rowLength, rowCount: image.height)
        }
        guard let digest else { return nil }
        self = digest
    }
}
#endif
