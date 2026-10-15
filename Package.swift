// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitGardener",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "GitGardenerCore"),
        .executableTarget(name: "GitGardener", dependencies: ["GitGardenerCore"]),
        .testTarget(name: "GitGardenerCoreTests", dependencies: ["GitGardenerCore"]),
    ]
)
