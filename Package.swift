// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Gedi",
    platforms: [.macOS("26.0")],
    targets: [
        // Pure logic. No AppKit/AVFoundation/Speech. Everything here is unit-tested.
        .target(name: "GediCore"),
        // macOS integrations (mic, speech recognition, audio, AppleScript, Piper process).
        .target(name: "GediSystem", dependencies: ["GediCore"]),
        .testTarget(name: "GediCoreTests", dependencies: ["GediCore"]),
    ],
    swiftLanguageModes: [.v5]
)
