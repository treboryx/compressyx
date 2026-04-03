// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Compressy",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Compressy",
            path: "Sources/Compressy"
        )
    ]
)
