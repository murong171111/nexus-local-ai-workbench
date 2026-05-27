// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NexusNative",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NexusNative", targets: ["NexusApp"])
    ],
    targets: [
        .executableTarget(name: "NexusApp")
    ]
)
