// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "quick",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "quick", targets: ["quick"])
    ],
    targets: [
        .target(name: "QuickCore"),
        .executableTarget(name: "quick", dependencies: ["QuickCore"]),
        .testTarget(name: "QuickCoreTests", dependencies: ["QuickCore"])
    ]
)
