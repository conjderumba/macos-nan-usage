// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NanMenubar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NanMenubar",
            path: "Sources/NanMenubar"
        )
    ]
)
