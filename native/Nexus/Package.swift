// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NexusNative",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "NexusBridge", targets: ["NexusBridge"]),
        .executable(name: "NexusNative", targets: ["NexusApp"])
    ],
    targets: [
        .target(name: "NexusBridge"),
        .executableTarget(name: "NexusApp", dependencies: ["NexusBridge"])
    ]
)
