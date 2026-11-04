// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "quick",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "quick", targets: ["quick"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.0")
    ],
    targets: [
        .target(name: "QuickCore", dependencies: ["Yams"]),
        .executableTarget(
            name: "quick",
            dependencies: ["QuickCore", .product(name: "ArgumentParser", package: "swift-argument-parser")]
        ),
        .testTarget(name: "QuickCoreTests", dependencies: ["QuickCore"])
    ]
)
