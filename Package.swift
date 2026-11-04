// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "quick",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "quick", targets: ["quick"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.0")
    ],
    targets: [
        .target(name: "QuickCore", dependencies: ["Yams"]),
        .executableTarget(name: "quick", dependencies: ["QuickCore"]),
        .testTarget(name: "QuickCoreTests", dependencies: ["QuickCore"])
    ]
)
