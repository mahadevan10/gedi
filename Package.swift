// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Gedi",
    platforms: [.macOS("26.0")],
    targets: [
        // Pure logic. No AppKit/AVFoundation/Speech. Everything here is unit-tested.
        .target(name: "GediCore"),
        .testTarget(name: "GediCoreTests", dependencies: ["GediCore"]),
    ],
    swiftLanguageModes: [.v5]
)
