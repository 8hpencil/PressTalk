// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "PressTalk",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/soffes/HotKey", from: "0.2.1")
    ],
    targets: [
        .executableTarget(
            name: "PressTalk",
            dependencies: [
                .product(name: "HotKey", package: "HotKey")
            ],
            path: "Sources/PressTalk",
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
