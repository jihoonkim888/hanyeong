// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Hanyeong",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic with no AppKit/IOKit dependency, so it can be unit tested.
        .target(name: "HanyeongCore"),
        .executableTarget(name: "Hanyeong", dependencies: ["HanyeongCore"]),
        .testTarget(name: "HanyeongCoreTests", dependencies: ["HanyeongCore"]),
    ]
)
