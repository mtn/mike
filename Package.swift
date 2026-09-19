// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Mike",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MikeCore", targets: ["MikeCore"]),
        .executable(name: "mike-gate", targets: ["MikeGate"]),
        .executable(name: "mike-probe", targets: ["MikeProbe"]),
    ],
    targets: [
        .target(name: "MikeCore"),
        .executableTarget(
            name: "MikeGate",
            dependencies: ["MikeCore"]
        ),
        .executableTarget(
            name: "MikeProbe",
            dependencies: ["MikeCore"]
        ),
        .testTarget(
            name: "MikeCoreTests",
            dependencies: ["MikeCore"]
        ),
    ]
)
