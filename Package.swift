// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "sshot",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "sshot",
            path: "mac/Sources/sshot",
            plugins: ["EmbedPayload"]
        ),
        // Turns VERSION and vm/ into Swift source so one binary can install the remote side.
        .executableTarget(name: "sshot-embed", path: "mac/Sources/sshot-embed"),
        .plugin(
            name: "EmbedPayload",
            capability: .buildTool(),
            dependencies: ["sshot-embed"],
            path: "mac/Plugins/EmbedPayload"
        ),
    ]
)
