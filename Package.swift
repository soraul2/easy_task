// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TodoDesktopMVP",
    platforms: [
        .macOS(.v26)
    ],
    targets: [
        .executableTarget(
            name: "TodoDesktopMVP",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "TodoDesktopMVPTests",
            dependencies: ["TodoDesktopMVP"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
