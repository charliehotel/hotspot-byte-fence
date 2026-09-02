// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "HotspotByteFence",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "HotspotByteFenceCore",
            targets: ["HotspotByteFenceCore"]
        ),
        .executable(
            name: "HotspotByteFence",
            targets: ["HotspotByteFence"]
        )
    ],
    targets: [
        .target(name: "HotspotByteFenceCore"),
        .executableTarget(
            name: "HotspotByteFence",
            dependencies: ["HotspotByteFenceCore"]
        ),
        .testTarget(
            name: "HotspotByteFenceCoreTests",
            dependencies: ["HotspotByteFenceCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
