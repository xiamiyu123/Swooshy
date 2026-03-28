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
        .target(
            name: "CMultitouchShim",
            path: "Sources/CMultitouchShim",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "Sweeesh",
            dependencies: ["CMultitouchShim"],
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
