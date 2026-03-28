// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Sweeesh",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "Sweeesh",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "SweeeshTests",
            dependencies: ["Sweeesh"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
