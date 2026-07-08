// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TodoDesktopMVP",
    platforms: [
        .iOS(.v18),
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "EasyTaskCore",
            targets: ["EasyTaskCore"]
        ),
        .executable(
            name: "TodoDesktopMVP",
            targets: ["TodoDesktopMVP"]
        ),
        .executable(
            name: "EasyTaskiOS",
            targets: ["EasyTaskiOS"]
        )
    ],
    targets: [
        .target(
            name: "EasyTaskCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "TodoDesktopMVP",
            dependencies: ["EasyTaskCore"]
        ),
        .executableTarget(
            name: "EasyTaskiOS",
            dependencies: ["EasyTaskCore"]
        ),
        .testTarget(
            name: "TodoDesktopMVPTests",
            dependencies: ["EasyTaskCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
