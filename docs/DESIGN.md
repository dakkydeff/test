# KindleToPDF — 設計書

対象: macOS 14 (Sonoma) 以降 / Swift 5.9+ / SwiftUI
目的: Kindle for Mac で開いている本を、**自分だけが使う目的で**、1ページずつ画面キャプチャして1つのPDFにまとめる。

## 0. 方針と制約（最重要）

- **DRM解除は一切しない。** Kindleのファイル(.azw/.kfx等)には触れない。画面に表示されたピクセルをキャプチャするだけ。
- 対象ウィンドウは **Kindle for Mac (bundle id `com.amazon.Kindle` / `com.amazon.Lassen`)**。ユーザーが選んだウィンドウのみをキャプチャする（画面全体ではない）。
- 必要な権限は2つ。アプリは両方の状態を表示し、未許可なら「システム設定を開く」ボタンを出す。
  - **画面収録** (Screen Recording) — ScreenCaptureKit によるウィンドウキャプチャ用
  - **アクセシビリティ** (Accessibility) — ページ送りキー送信 (CGEvent) 用
- ビルド検証はMac上でのみ可能。実装はLinuxコンテナで行うため、**ロジック部分（終端判定・PDF組立・差分比較）は AppKit 非依存の純粋Swiftに分離して XCTest でテスト可能にする**。

## 1. 動作フロー（ユーザー視点）

1. Kindle for Mac で本を開き、**最初のページ**を表示しておく（ユーザーの手動操作）。
2. KindleToPDF を起動 → ウィンドウ一覧から Kindle のウィンドウを選ぶ。
3. 設定: ページ送り間隔（秒, 既定 1.0）、最大ページ数（既定 2000）、出力先、余白トリミング(px, 任意)。
4. 「開始」→ アプリは Kindle をアクティブにし、以下をループ:
   - ウィンドウをキャプチャ
   - 直前のフレームと比較。**同一フレームが連続 N 回 (既定 3)** なら本の終端とみなして終了
   - 右矢印キー(→)を Kindle プロセスに送信してページ送り
   - 指定秒待つ
5. 終了時、収集した画像からPDFを生成して保存。進捗・ページ数・ログをUIに表示。
6. 「停止」でいつでも中断可能。中断時点までのページでPDFを保存するか選べる。

## 2. アーキテクチャ

```
KindleToPDF/
├── Package.swift                 # SwiftPM。executableTarget + 純粋ロジックtarget + tests
├── Sources/
│   ├── CaptureCore/              # ★AppKit/ScreenCaptureKit非依存。Linuxでもコンパイル可能なロジック
│   │   ├── FrameDigest.swift     # 画像バイト列→ハッシュ(FNV-1a 64bit)。差分比較に使う
│   │   ├── EndOfBookDetector.swift  # 「同一フレーム連続N回で終了」の状態機械
│   │   ├── CaptureSession.swift  # ループの純粋な状態遷移 (idle/running/stopping/finished/failed)
│   │   └── CaptureConfig.swift   # 設定値 (interval, maxPages, stableFrames, crop insets)
│   └── KindleToPDF/              # macOSアプリ本体 (SwiftUI + AppKit)
│       ├── KindleToPDFApp.swift  # @main
│       ├── UI/
│       │   ├── ContentView.swift        # メイン画面
│       │   ├── WindowPickerView.swift   # SCShareableContent からKindleウィンドウ一覧
│       │   ├── PermissionsView.swift    # 権限状態と「設定を開く」
│       │   └── ProgressView.swift       # 進捗/サムネイル/ログ
│       ├── Services/
│       │   ├── WindowCapturer.swift     # ScreenCaptureKit (SCScreenshotManager) で単一ウィンドウを CGImage に
│       │   ├── PageTurner.swift         # CGEvent で → キーを Kindle pid にpost
│       │   ├── PermissionChecker.swift  # CGPreflightScreenCaptureAccess / AXIsProcessTrusted
│       │   ├── PDFBuilder.swift         # [CGImage] → PDF (CGContext PDF、画像を等倍で1ページずつ)
│       │   └── CaptureRunner.swift      # 上記を組み合わせた実行ループ (actor / @MainActor ObservableObject)
│       └── Resources/Info.plist         # NSScreenCaptureUsageDescription 等
├── Tests/CaptureCoreTests/       # XCTest (Linuxでも swift test 可能)
├── scripts/
│   └── build-app.sh              # swift build -c release → KindleToPDF.app バンドル生成 → ad-hoc codesign
├── Makefile                      # make app / make test / make clean
├── README.md                     # 使い方・権限設定・注意事項（個人利用のみ）
└── docs/DESIGN.md                # 本書
```

### 2.1 CaptureCore（純粋ロジック）仕様

```swift
public struct CaptureConfig: Equatable, Sendable {
    public var pageInterval: TimeInterval = 1.0   // 0.3 ... 10
    public var maxPages: Int = 2000               // 1 ... 10000
    public var stableFramesToStop: Int = 3        // 2 ... 10
    public var cropInsets: CropInsets = .zero     // top/left/bottom/right (px, 元画像スケール)
}

public struct FrameDigest: Hashable, Sendable {
    public init(bytes: UnsafeRawBufferPointer)    // FNV-1a 64bit
    public init<C: Collection>(_ bytes: C) where C.Element == UInt8
}

public enum EndOfBookDecision: Equatable { case `continue`, endOfBook }

public struct EndOfBookDetector {
    public init(stableFramesToStop: Int)
    /// 新しいフレームのダイジェストを投入。直前と同一なら連続カウント++、違えばリセット。
    /// カウントが stableFramesToStop に達したら .endOfBook
    public mutating func observe(_ digest: FrameDigest) -> EndOfBookDecision
    public var consecutiveIdenticalCount: Int { get }
}

public enum CaptureState: Equatable {
    case idle
    case running(page: Int)
    case stopping
    case finished(pages: Int, reason: FinishReason)
    case failed(message: String)
}
public enum FinishReason: Equatable { case endOfBook, maxPagesReached, userStopped }
```

- 終端判定の注意: 連続同一カウントは「**ページ送り後に**撮ったフレームが直前と同じ」で数える。最初のフレームは比較対象なし。
- 終端で停止したとき、**末尾の重複フレーム (stableFramesToStop - 1 枚) は PDF に含めない**（同じ最終ページが複数枚入るのを防ぐ）。この「何枚捨てるか」の計算も CaptureCore に置き、テストする。
- maxPages に達したら `.maxPagesReached` で終了。

### 2.2 WindowCapturer

- `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)` でウィンドウ列挙。`owningApplication.bundleIdentifier` が `com.amazon.Kindle` or `com.amazon.Lassen` のものを優先表示、他は折りたたみで表示（ユーザーが別名のKindleを使う場合のため）。
- `SCContentFilter(desktopIndependentWindow:)` + `SCStreamConfiguration`（width/height は window.frame × backingScaleFactor、`showsCursor = false`、`capturesShadowsOnly = false`、`ignoreShadowsDisplay = true`）。
- `SCScreenshotManager.captureImage(contentFilter:configuration:)` (macOS 14+) で `CGImage` を取得。
- 取得後、`cropInsets` が非ゼロなら `CGImage.cropping(to:)`。

### 2.3 PageTurner

- `CGEvent(keyboardEventSource:virtualKey: 0x7C /*→*/, keyDown:)` を `postToPid(kindlePid)`。keyDown → 30ms → keyUp。
- 送信前に `NSRunningApplication(processIdentifier:)?.activate()` で Kindle を前面に（最初の1回 + 各ページ送り前に `isActive` でなければ再activate）。
- アクセシビリティ未許可なら事前に失敗させる（`AXIsProcessTrustedWithOptions` で prompt）。

### 2.4 PDFBuilder

- `CGContext(consumer:mediaBox:)` を使い、各画像を **1ページ = 画像のピクセルサイズ (pt=px として 72dpi 扱い)** で描画。PDFKit の `PDFPage(image:)` は再圧縮・解像度低下の懸念があるため使わない。
- メタデータ: Title (ユーザー入力、既定は Kindle ウィンドウタイトル)、Creator "KindleToPDF"。
- メモリ対策: 画像は撮影ごとに **PNGで一時ディレクトリに書き出し**、PDF生成時に順次読み込む（2000ページを全部メモリに持たない）。一時ディレクトリは成功時に削除、失敗時は残してパスをログに出す。

### 2.5 CaptureRunner（実行ループ）

- `@MainActor final class CaptureRunner: ObservableObject` で `@Published var state: CaptureState`, `pageCount`, `lastThumbnail: NSImage?`, `log: [String]`。
- 実行は `Task { }` 内で `try Task.checkCancellation()` を各ステップで確認。停止ボタンは `task.cancel()`。
- 擬似コード:

```
activate(kindle)
sleep(0.5)
detector = EndOfBookDetector(n)
for page in 1...maxPages:
    img = capture(); write png; digest = FrameDigest(img rawBytes)
    if page > 1, detector.observe(digest) == .endOfBook: reason = .endOfBook; break
    update UI (page, thumbnail)
    turnPage(); sleep(interval)
else: reason = .maxPagesReached
drop trailing duplicates (if endOfBook)
build pdf → save
```

- `FrameDigest` の入力は `CGImage.dataProvider?.data` の生バイト。

### 2.6 UI（ContentView）

1行目: 権限ステータス2つ（緑/赤 + 設定を開くボタン）
2行目: ウィンドウ選択 Picker + 更新ボタン
3行目: 間隔 Stepper / 最大ページ TextField / 安定フレーム数 Stepper / トリミング 4つの数値
4行目: 出力先 (NSSavePanel) / タイトル
5行目: 開始 / 停止 ボタン、ProgressView、現在ページ数、サムネイル、ログ(ScrollView)
注意書き: 「個人利用のみ。著作権法上の私的複製の範囲内でご利用ください。」

## 3. ビルドと配布

- `make app` → `scripts/build-app.sh`:
  1. `swift build -c release --product KindleToPDF`
  2. `build/KindleToPDF.app/Contents/{MacOS,Resources}` を作成、バイナリと `Info.plist` をコピー
  3. `codesign --force --deep --sign - build/KindleToPDF.app` (ad-hoc)。**bundle id を固定しないと TCC 権限が毎回リセットされる**ので `CFBundleIdentifier = jp.local.KindleToPDF` を固定。
- `make test` → `swift test`（CaptureCore のみ。macOS以外でも通る）
- Info.plist 必須キー: `CFBundleIdentifier`, `CFBundleName`, `CFBundleExecutable`, `CFBundlePackageType=APPL`, `LSMinimumSystemVersion=14.0`, `NSScreenCaptureUsageDescription`, `NSAppleEventsUsageDescription`(不要なら省略可), `LSUIElement=false`, `NSHighResolutionCapable=true`。
- Package.swift では `KindleToPDF` ターゲットに `.unsafeFlags` は使わない。macOS 専用APIは `#if os(macOS)` で囲み、Linux で `swift build` した際は CaptureCore と tests だけがビルドされるよう `KindleToPDF` ターゲット全体を `#if os(macOS)` で包む（ファイル先頭/末尾）。

## 4. テスト（Tests/CaptureCoreTests）

- `FrameDigestTests`: 同一バイト→同一、1バイト違い→異なる、空→定数。
- `EndOfBookDetectorTests`: n=3 で A,A,A → 3回目で endOfBook / A,B,A,A,A → 5回目 / A,A,B,B,B → 5回目 / n=2 境界。
- `TrailingDuplicateTests`: endOfBook で止まったとき捨てる枚数 = n-1、maxPages/userStopped なら 0。
- `CaptureConfigTests`: clamp (interval<0.3→0.3, maxPages>10000→10000 等)。

## 5. 実装者（Opus）への指示

- 上記のファイル構成・公開API名をそのまま使うこと（レビューはこの設計書と突き合わせて行う）。
- macOS固有コードはコンパイルできない環境で書くため、**APIシグネチャは正確に**（ScreenCaptureKit / CGEvent / CGContext PDF）。曖昧な箇所はコメントで `// NOTE(verify-on-mac):` を付ける。
- README には権限設定手順、`make app` 手順、「Kindle側で最初のページを開いてから開始」の注意、個人利用限定の注意を書く。
- Linux で `swift build` / `swift test` が通る構成を意識する（このコンテナには swift が無いので実行はできないが、構成上通るように）。

## 6. 実装時の差分（レビューで承認済み）

- 進捗ビューは `UI/CaptureProgressView.swift` / 型名 `CaptureProgressView`（SwiftUI.ProgressView との衝突回避）。
- `UnsupportedPlatformMain.swift`（`#if !os(macOS)`）を追加。Linux で `swift build` した際に実行ターゲットのエントリポイントが無くてリンクに失敗するのを防ぐ。
- 終端判定は **1ページ目から** `observe` する（擬似コードの `page > 1` ガードは廃止）。同一フレームの連続長 = ディスク上の同一PNG枚数となり、`trailingFramesToDrop = n-1` と整合する。
- 停止時は「PDF を保存 / 破棄」を選べる（`CaptureRunner.partialSavePrompt` + alert）。
- 撮影中に KindleToPDF が前面になったら一時停止し、Kindle がクリックされたら再開する（毎回 Kindle を強制的に前面にすると停止ボタンが押せなくなるため）。
- トリミング後の `CGImage` は新しいビットマップに描き直す（`cropping(to:)` は親のピクセルデータを共有し得るため、ハッシュに切り落とした領域が混入するのを防ぐ）。
- 保存先未指定時はデスクトップに、既存ファイルを上書きしない名前で保存。タイトル既定値はウィンドウタイトル。
- ad-hoc 署名では再ビルドごとに署名が変わり TCC 権限が外れ得る。README に `tccutil reset` と `CODESIGN_IDENTITY` の案内を記載。
- PDF 書き出し中は「停止」を無効化（`CaptureRunner.isBuildingPDF`）。

## 7. バックグラウンドモード（v1.1）

ユーザーが他の画面に移ると撮影が止まる問題への対応。`CaptureConfig.bringsKindleToFront`（既定 `false`）を追加。

- **バックグラウンドモード (`false`, 既定)**: Kindle を activate しない。`SCShareableContent` は `onScreenWindowsOnly: false` で取得し、別 Space や他ウィンドウの背面にある Kindle ウィンドウも `desktopIndependentWindow` で撮る。ページ送りは `CGEvent.postToPid` のみ（プロセス宛てなので他アプリの入力には混ざらない）。KindleToPDF が前面でも一時停止しない。最小化されたウィンドウは撮れない。
- **前面モード (`true`)**: 従来どおり。ページ送り前に Kindle を activate し、KindleToPDF が前面なら一時停止。背面の Kindle がキーに反応しないビルド向けのフォールバック。
- ウィンドウ一覧は Kindle のウィンドウなら画面外（別 Space）でも表示し、他アプリは `isOnScreen` のものだけ表示。
