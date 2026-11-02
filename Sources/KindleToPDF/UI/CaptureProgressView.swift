#if os(macOS)
import CaptureCore
import SwiftUI

/// Status, page count, latest thumbnail and log of the current run.
/// (Named CaptureProgressView to avoid clashing with SwiftUI.ProgressView.)
struct CaptureProgressView: View {
    @ObservedObject var runner: CaptureRunner

    var body: some View {
        GroupBox("進捗") {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(statusText)
                        .font(.headline)
                    if runner.isRunning {
                        ProgressView()
                            .progressViewStyle(.linear)
                    }
                    Text("撮影済み: \(runner.pageCount) ページ")
                        .monospacedDigit()
                    logView
                }
                thumbnail
            }
        }
    }

    private var statusText: String {
        switch runner.state {
        case .idle:
            return "待機中"
        case .running(let page):
            return page == 0 ? "準備中…" : "撮影中…（\(page) ページ目）"
        case .stopping:
            return "停止処理中…"
        case let .finished(pages, reason):
            return "完了: \(pages) ページ（\(reason.displayName)）"
        case .failed(let message):
            return "失敗: \(message)"
        }
    }

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(runner.log.enumerated()), id: \.offset) { item in
                        Text(item.element)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(item.offset)
                    }
                }
                .padding(6)
            }
            .frame(minHeight: 140, maxHeight: 200)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onChange(of: runner.log.count) { _, count in
                guard count > 0 else { return }
                proxy.scrollTo(count - 1, anchor: .bottom)
            }
        }
    }

    private var thumbnail: some View {
        Group {
            if let image = runner.lastThumbnail {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.1))
                    .overlay { Text("サムネイル").foregroundStyle(.secondary) }
            }
        }
        .frame(width: 180, height: 240)
    }
}

extension FinishReason {
    var displayName: String {
        switch self {
        case .endOfBook:
            return "本の終わりを検出"
        case .maxPagesReached:
            return "最大ページ数に到達"
        case .userStopped:
            return "ユーザーが停止"
        }
    }
}
#endif
