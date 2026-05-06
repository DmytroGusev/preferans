// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PreferansEngine",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
        .macOS(.v14),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "PreferansEngine", targets: ["PreferansEngine"]),
        .library(name: "PreferansApp", targets: ["PreferansApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "PreferansEngine",
            swiftSettings: [.swiftLanguageMode(.v5)]
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
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PreferansEngineTests",
            dependencies: [
                "PreferansEngine",
                "PreferansApp",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
                .product(name: "Dependencies", package: "swift-dependencies"),
                .product(name: "DependenciesTestSupport", package: "swift-dependencies")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
