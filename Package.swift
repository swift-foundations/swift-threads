// swift-tools-version: 6.3

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
        .library(name: "Thread Pool", targets: ["Thread Pool"]),
    ],
    dependencies: [
        .package(path: "../swift-kernel"),
        .package(path: "../swift-executors"),
        .package(path: "../../swift-primitives/swift-async-primitives"),
        .package(path: "../../swift-primitives/swift-algebra-primitives"),
    ],
    targets: [
        .target(
            name: "Thread Pool",
            dependencies: [
                .product(name: "Executors", package: "swift-executors"),
                .product(name: "Async Semaphore Primitives", package: "swift-async-primitives"),
                .product(name: "Algebra Primitives", package: "swift-algebra-primitives"),
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
