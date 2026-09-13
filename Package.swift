// swift-tools-version:6.0
import PackageDescription

let swiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Ebb",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Ebb", targets: ["Ebb"]),
        .executable(name: "EbbCLI", targets: ["EbbCLI"]),
        .library(name: "EbbCore", targets: ["EbbCore"]),
    ],
    targets: [
        .target(name: "EbbCore", path: "Sources/EbbCore", swiftSettings: swiftSettings),
        .executableTarget(
            name: "Ebb",
            dependencies: ["EbbCore"],
            path: "Sources/Ebb",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "EbbCLI",
            dependencies: ["EbbCore"],
            path: "Sources/EbbCLI",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "EbbCoreTests",
            dependencies: ["EbbCore"],
            path: "Tests/EbbCoreTests",
            swiftSettings: swiftSettings
        ),
    ]
)
