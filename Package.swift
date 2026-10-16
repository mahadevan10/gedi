// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Gedi",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "gedi-debug", targets: ["GediDebug"]),
    ],
    targets: [
        // Pure logic. No AppKit/AVFoundation/Speech. Everything here is unit-tested.
        .target(name: "GediCore"),
        // macOS integrations (mic, speech recognition, audio, AppleScript, Piper process).
        .target(name: "GediSystem", dependencies: ["GediCore"]),
        // Command-line tool for exercising each subsystem on its own.
        .executableTarget(name: "GediDebug", dependencies: ["GediCore", "GediSystem"]),
        .testTarget(name: "GediCoreTests", dependencies: ["GediCore"]),
    ],
    swiftLanguageModes: [.v5]
)
