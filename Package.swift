// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "pls",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "pls", targets: ["pls"])
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.8.0")
    ],
    targets: [
        .target(name: "PlsCore", dependencies: ["Yams"]),
        // Line editing for prompts: libedit ships with macOS.
        .target(name: "CEditLine", linkerSettings: [.linkedLibrary("edit")]),
        .executableTarget(
            name: "pls",
            dependencies: [
                "PlsCore", "CEditLine", .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(name: "PlsCoreTests", dependencies: ["PlsCore"])
    ]
)
