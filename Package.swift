// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Signal",
    platforms: [
        .iOS(.v15),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "SignalCore",
            targets: ["SignalCore"]
        ),
        .library(
            name: "DuplicateContentDetection",
            targets: ["DuplicateContentDetection"]
        ),
        .executable(
            name: "MyTool",
            targets: ["MyTool"]
        )
    ],
    dependencies: [
        // Apple Swift open-source packages
        .package(url: "https://github.com/apple/swift-algorithms.git", exact: "1.2.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.5.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms.git", exact: "1.0.0"),
        .package(url: "https://github.com/apple/swift-atomics.git", exact: "1.2.0"),
        .package(url: "https://github.com/apple/swift-collections.git", exact: "1.1.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "3.2.0"),
        .package(url: "https://github.com/apple/swift-log.git", exact: "1.6.3"),
        .package(url: "https://github.com/apple/swift-numerics.git", exact: "1.0.2")
    ],
    targets: [
        // Core utilities and logic
        .target(
            name: "SignalCore",
            dependencies: [
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "Atomics", package: "swift-atomics"),
                .product(name: "Collections", package: "swift-collections"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Numerics", package: "swift-numerics")
            ],
            path: "SignalCore/Sources"
        ),
        // Duplicate content detection module
        .target(
            name: "DuplicateContentDetection",
            dependencies: [
                "SignalCore",
                .product(name: "Logging", package: "swift-log")
            ],
            path: "DuplicateContentDetection/Services"
        ),
        // Tests for DuplicateContentDetection
        .testTarget(
            name: "DuplicateContentDetectionTests",
            dependencies: [
                "DuplicateContentDetection",
                "SignalCore",
                .product(name: "Logging", package: "swift-log")
            ],
            path: "DuplicateContentDetection/Tests"
        ),
        // Command-line utility target
        .executableTarget(
            name: "MyTool",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log")
            ],
            path: "MyTool/Sources"
        )
    ]
)
