// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PressTalk",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.1"),
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "PressTalk",
            dependencies: [
                .product(name: "HotKey", package: "HotKey"),
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "Sources/PressTalk",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "PressTalkTests",
            dependencies: ["PressTalk"],
            path: "Tests/PressTalkTests"
        ),
    ]
)
