// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PreferansEngine",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8)
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
            ]
        ),
        .testTarget(
            name: "PreferansEngineTests",
            dependencies: ["PreferansEngine", "PreferansApp"]
        )
    ]
)
