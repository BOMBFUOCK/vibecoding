// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIEmailCLI",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0")
    ],
    targets: [
        .executableTarget(
            name: "cli",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SQLite", package: "SQLite.swift")
            ],
            path: "Sources/CLI"
        ),
        .testTarget(
            name: "CLITests",
            dependencies: ["cli"],
            path: "Tests/CLI"
        )
    ]
)
