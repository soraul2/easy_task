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
        )
    ],
    targets: [
        .target(name: "EasyTaskCore"),
        .testTarget(
            name: "TodoDesktopMVPTests",
            dependencies: ["EasyTaskCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
