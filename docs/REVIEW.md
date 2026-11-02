# レビュー記録（設計: Fable / 実装: Opus / レビュー: Fable）

対象: 初回実装（`Sources/`, `Tests/`, `scripts/`, `Makefile`, `README.md`）
結論: **設計書どおり。修正1件を適用してマージ可。** ただし本コンテナ（Linux、Swift なし）では一度もコンパイルしていないため、Mac 上での `make test` / `make app` による検証が必須。

## 設計との突き合わせ

| 項目 | 結果 |
| --- | --- |
| ファイル構成・公開API名 (2.1) | 一致。`trailingFramesToDrop` / `pagesToKeep` も追加 |
| 終端判定の意味論 | A,A,A → 3枚目で終了。endOfBook 時に n−1 枚を捨てると最終ページがちょうど1枚残る。シミュレーションテストあり |
| WindowCapturer (2.2) | SCShareableContent / SCContentFilter(desktopIndependentWindow:) / SCScreenshotManager.captureImage を使用。Kindle の bundle id 優先。トリミング後に再描画 |
| PageTurner (2.3) | 0x7C keyDown→30ms→keyUp を postToPid。未アクティブなら activate |
| PDFBuilder (2.4) | CGContext(consumer:mediaBox:)、1ページ=画像ピクセルサイズ、Title/Creator 設定、1枚ずつ遅延読み込み、一時ファイル経由で原子的に保存 |
| CaptureRunner (2.5) | PNG を一時ディレクトリへ、FrameDigest は dataProvider の生バイト（行パディング除外）、Task.cancel で停止、成功時に一時ディレクトリ削除 |
| UI (2.6) | 権限 / ウィンドウ選択 / 設定 / 出力 / 開始停止 / 進捗 / 注意書き、すべて日本語 |
| ビルド (3) | build-app.sh で .app 組立 + ad-hoc codesign、bundle id 固定 |
| テスト (4) | 4ファイル + CaptureSessionTests。FNV-1a の既知ベクタ ("a", "foobar") を検証 |

## 修正したもの

1. **PDF 書き出し中に「停止」が押せた。** `Task.cancel` は detached の PDF 生成には届かず、状態だけ「停止処理中」になって誤解を招くため、`isBuildingPDF` を追加して停止ボタンを無効化し、`stop()` も無視するようにした。

## 指摘なし・承認した設計差分

`docs/DESIGN.md` の「6. 実装時の差分」を参照。いずれも妥当。

## Mac 上で必ず確認すること（NOTE(verify-on-mac)）

- `SCStreamConfiguration.capturesShadowsOnly / ignoreShadowsDisplay / ignoreShadowsSingleWindow`、`SCContentFilter.pointPixelScale`（いずれも macOS 14+）
- `NSApp.yieldActivation(to:)` → `activate(options: [])` で Kindle が前面に来るか
- 矢印キーに付けている `.maskNumericPad | .maskSecondaryFn` フラグで Kindle がページ送りするか（しなければフラグを外す）
- `kAXTrustedCheckOptionPrompt.takeUnretainedValue()` のコンパイル
- 長い本で PDF 生成中のメモリが平坦か（CGPDFContext が endPDFPage ごとに書き出すか）
- 連続キャプチャのピクセルが本当に一致するか（Kindle 側のアニメーション・カーソル点滅等で終端検出が効かない場合は、将来的に「差分ピクセル率 < 閾値」への緩和を検討）

## 既知のリスク（コードの欠陥ではない）

- ピクセル完全一致による終端検出は Kindle の UI 変化に弱い。最大ページ数が安全弁。
- ad-hoc 署名は再ビルドで TCC 権限が外れる。README に対処を記載済み。
