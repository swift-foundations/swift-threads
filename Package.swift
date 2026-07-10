// swift-tools-version: 6.3.3

import PackageDescription

let package = Package(
    name: "swift-threads",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
        .watchOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        // MARK: - Variants
        .library(name: "Thread Barrier", targets: ["Thread Barrier"]),
        .library(name: "Thread Gate", targets: ["Thread Gate"]),
        .library(name: "Thread Semaphore", targets: ["Thread Semaphore"]),
        .library(name: "Thread Worker", targets: ["Thread Worker"]),
        .library(name: "Thread Pool", targets: ["Thread Pool"]),
        .library(name: "Thread Actor", targets: ["Thread Actor"]),
        // MARK: - Umbrella
        .library(name: "Threads", targets: ["Threads"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-foundations/swift-kernel.git", branch: "main"),
        .package(url: "https://github.com/swift-foundations/swift-executors.git", branch: "main"),
        .package(url: "https://github.com/swift-foundations/swift-synchronizers.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-async-primitives.git", branch: "main"),
        .package(url: "https://github.com/swift-primitives/swift-either-primitives.git", branch: "main"),
    ],
    targets: [
        // MARK: - Coordination variants
        .target(
            name: "Thread Barrier",
            dependencies: [
                .product(name: "Synchronizer Blocking", package: "swift-synchronizers"),
            ]
        ),
        .target(
            name: "Thread Gate",
            dependencies: [
                .product(name: "Synchronizer Blocking", package: "swift-synchronizers"),
            ]
        ),
        .target(
            name: "Thread Semaphore",
            dependencies: [
                .product(name: "Synchronizer Blocking", package: "swift-synchronizers"),
            ]
        ),
        .target(
            name: "Thread Worker",
            dependencies: [
                .product(name: "Synchronizer Blocking", package: "swift-synchronizers"),
            ]
        ),

        // MARK: - Dispatch
        .target(
            name: "Thread Pool",
            dependencies: [
                .product(name: "Executors", package: "swift-executors"),
                .product(name: "Async Semaphore Primitives", package: "swift-async-primitives"),
                .product(name: "Either Primitives", package: "swift-either-primitives"),
            ]
        ),
        .target(
            name: "Thread Actor",
            dependencies: [
                .product(name: "Executors", package: "swift-executors"),
            ]
        ),

        // MARK: - Umbrella
        .target(
            name: "Threads",
            dependencies: [
                "Thread Barrier",
                "Thread Gate",
                "Thread Semaphore",
                "Thread Worker",
                "Thread Pool",
                "Thread Actor",
            ]
        ),

        // MARK: - Tests
        .testTarget(
            name: "Thread Semaphore Tests",
            dependencies: [
                "Thread Semaphore",
                "Thread Gate",
                .product(name: "Kernel Test Support", package: "swift-kernel"),
            ]
        ),
        .testTarget(
            name: "Thread Pool Tests",
            dependencies: [
                "Thread Pool",
                .product(name: "Kernel Test Support", package: "swift-kernel"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("LifetimeDependence"),
        .enableExperimentalFeature("Lifetimes"),
        .enableExperimentalFeature("SuppressedAssociatedTypes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("LifetimeDependence"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
