// swift-tools-version: 6.0

import PackageDescription

let isEngineTestLane = Context.environment["PREFERANS_ENGINE_TESTS_ONLY"] == "1"

let products: [Product]
let dependencies: [Package.Dependency]
let targets: [Target]

if isEngineTestLane {
    products = [
        .library(name: "PreferansEngine", targets: ["PreferansEngine"])
    ]
    dependencies = []
    targets = [
        .target(name: "PreferansEngine"),
        .target(
            name: "PreferansEngineTestSupport",
            dependencies: ["PreferansEngine"],
            path: "Tests/PreferansEngineTestSupport"
        ),
        .testTarget(
            name: "PreferansEngineCLITests",
            dependencies: ["PreferansEngine", "PreferansEngineTestSupport"],
            path: "Tests/PreferansEngineCLITests"
        )
    ]
} else {
    products = [
        .library(name: "PreferansEngine", targets: ["PreferansEngine"]),
        .library(name: "PreferansApp", targets: ["PreferansApp"])
    ]
    dependencies = [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.5.0")
    ]
    targets = [
        .target(name: "PreferansEngine"),
        .target(
            name: "PreferansEngineTestSupport",
            dependencies: ["PreferansEngine"],
            path: "Tests/PreferansEngineTestSupport"
        ),
        .testTarget(
            name: "PreferansEngineCLITests",
            dependencies: ["PreferansEngine", "PreferansEngineTestSupport"],
            path: "Tests/PreferansEngineCLITests"
        ),
        .testTarget(
            name: "PreferansEngineTests",
            dependencies: ["PreferansEngine", "PreferansEngineTestSupport"],
            path: "Tests/PreferansEngineCoreTests"
        ),
        .target(
            name: "PreferansApp",
            dependencies: [
                "PreferansEngine",
                .product(name: "Dependencies", package: "swift-dependencies")
            ],
            path: "Preferans",
            exclude: [
                "Assets.xcassets",
                "Preferans.entitlements",
                "PreferansApp.swift",
                "Support/Preferans.entitlements.example"
            ],
            resources: [
                .process("Resources/Localizable.xcstrings")
            ]
        ),
        .testTarget(
            name: "PreferansAppTests",
            dependencies: [
                "PreferansEngine",
                "PreferansEngineTestSupport",
                "PreferansApp",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesTestSupport", package: "swift-dependencies")
            ],
            path: "Tests/PreferansEngineTests",
            exclude: ["__Snapshots__"]
        )
    ]
}

let package = Package(
    name: "PreferansEngine",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
        .macOS(.v14),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: products,
    dependencies: dependencies,
    targets: targets
)
