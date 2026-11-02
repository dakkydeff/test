#if os(macOS)
import CoreGraphics
import Foundation
import ImageIO

enum PDFBuilderError: LocalizedError {
    case noPages
    case cannotCreateContext
    case unreadableImage(URL)

    var errorDescription: String? {
        switch self {
        case .noPages:
            return "PDF にするページがありません。"
        case .cannotCreateContext:
            return "PDF の作成を開始できませんでした。"
        case .unreadableImage(let url):
            return "画像を読み込めませんでした: \(url.lastPathComponent)"
        }
    }
}

/// Assembles page images into a single PDF with Core Graphics.
///
/// Each image becomes one page whose media box equals the image's pixel size
/// (1 px = 1 pt, i.e. 72 dpi), so nothing is resampled. PDFKit's
/// `PDFPage(image:)` is deliberately avoided.
enum PDFBuilder {
    static let creator = "KindleToPDF"

    /// Writes `imageURLs` (in order) to `outputURL`, replacing any existing file.
    /// Images are decoded one at a time to keep memory flat for long books.
    static func build(
        imageURLs: [URL],
        outputURL: URL,
        title: String,
        progress: ((_ completed: Int, _ total: Int) -> Void)? = nil
    ) throws {
        guard !imageURLs.isEmpty else { throw PDFBuilderError.noPages }

        // Render to a temporary file first so a failure never leaves a broken PDF behind.
        let fileManager = FileManager.default
        let temporaryURL = fileManager.temporaryDirectory
            .appendingPathComponent("KindleToPDF-\(UUID().uuidString).pdf")
        defer { try? fileManager.removeItem(at: temporaryURL) }

        try render(imageURLs: imageURLs, to: temporaryURL, title: title, progress: progress)

        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: outputURL)
    }

    private static func render(
        imageURLs: [URL],
        to url: URL,
        title: String,
        progress: ((Int, Int) -> Void)?
    ) throws {
        let documentInfo: [String: Any] = [
            kCGPDFContextTitle as String: title,
            kCGPDFContextCreator as String: creator,
        ]
        // Default media box; every page overrides it with its own size.
        var defaultMediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &defaultMediaBox, documentInfo as CFDictionary)
        else { throw PDFBuilderError.cannotCreateContext }
        defer { context.closePDF() }

        // NOTE(verify-on-mac): confirm memory stays flat on long books, i.e. that the PDF
        // context writes each page's image data at endPDFPage() instead of holding it until closePDF().
        let sourceOptions = [kCGImageSourceShouldCache as String: false] as CFDictionary

        for (index, imageURL) in imageURLs.enumerated() {
            try autoreleasepool {
                guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, sourceOptions),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, sourceOptions)
                else { throw PDFBuilderError.unreadableImage(imageURL) }

                var mediaBox = CGRect(x: 0, y: 0, width: image.width, height: image.height)
                // kCGPDFContextMediaBox expects a CFData holding a CGRect by value.
                let mediaBoxData = withUnsafeBytes(of: &mediaBox) { Data($0) }
                let pageInfo = [kCGPDFContextMediaBox as String: mediaBoxData] as CFDictionary

                context.beginPDFPage(pageInfo)
                context.draw(image, in: mediaBox)
                context.endPDFPage()
            }
            progress?(index + 1, imageURLs.count)
        }
    }
}
#endif
