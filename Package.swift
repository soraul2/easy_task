// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PlanBase",
    platforms: [
        .iOS(.v18),
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "PlanBaseCore",
            targets: ["PlanBaseCore"]
        )
    ],
    targets: [
        // Keep this module name stable because the shipped SwiftData schemas
        // were compiled in it. PlanBaseCore is the public product surface.
        .target(
            name: "EasyTaskCore",
            path: "shared/Core"
        ),
        .target(
            name: "PlanBaseCore",
            dependencies: ["EasyTaskCore"],
            path: "shared/PlanBaseCore"
        ),
        .testTarget(
            name: "PlanBaseCoreTests",
            dependencies: ["PlanBaseCore", "EasyTaskCore"],
            path: "shared/Tests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
