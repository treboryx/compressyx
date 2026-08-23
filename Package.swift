// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Compressyx",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Compressyx",
            path: "Sources/Compressyx"
        )
    ]
)
