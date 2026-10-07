// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "sshot",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "sshot", path: "Sources/sshot")
    ]
)
