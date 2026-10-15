// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "InstitutionalApp",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .executable(name: "InstitutionalApp", targets: ["InstitutionalApp"])
    ],
    dependencies: [
        // No external dependencies - only Foundation, Combine, SwiftUI, and system frameworks
    ],
    targets: [
        .executableTarget(
            name: "InstitutionalApp",
            dependencies: [],
            path: "Sources/InstitutionalApp",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)