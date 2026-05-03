// swift-tools-version: 5.9

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
    targets: [
        .target(name: "PreferansEngine"),
        .target(
            name: "PreferansApp",
            dependencies: ["PreferansEngine"],
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
            name: "PreferansEngineTests",
            dependencies: ["PreferansEngine", "PreferansApp"]
        )
    ]
)
