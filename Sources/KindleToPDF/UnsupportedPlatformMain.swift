#if !os(macOS)
// The app is macOS-only. This entry point exists solely so the executable
// target still links when the package is built on Linux (CaptureCore + tests).
@main
enum UnsupportedPlatformMain {
    static func main() {
        print("KindleToPDF は macOS 専用です。")
    }
}
#endif
