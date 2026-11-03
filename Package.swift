// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KindleToPDF",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "KindleToPDF", targets: ["KindleToPDF"]),
        .library(name: "CaptureCore", targets: ["CaptureCore"]),
    ],
    targets: [
        // Pure Swift (Foundation only) logic; builds and tests on Linux too.
        .target(name: "CaptureCore"),

        // macOS app. Every macOS source file is wrapped in `#if os(macOS)`;
        // UnsupportedPlatformMain.swift supplies an entry point elsewhere so
        // `swift build` still links on Linux.
        .executableTarget(
            name: "KindleToPDF",
            dependencies: ["CaptureCore"],
            // Info.plist and the icon are copied into the .app bundle by
            // scripts/build-app.sh (SwiftPM does not allow Info.plist as a resource).
            exclude: ["Resources"],
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit", .when(platforms: [.macOS])),
            ]
        ),

        .testTarget(name: "CaptureCoreTests", dependencies: ["CaptureCore"]),
    ]
)
