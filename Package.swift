// swift-tools-version: 6.4
import PackageDescription

let approachable: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]
let mainActor = approachable + [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "bridge",
    platforms: [.macOS(.v27)],
    dependencies: [
        .package(url: "https://github.com/automerge/automerge-swift", exact: "0.7.2"),
    ],
    targets: [
        .target(name: "BridgeCore", swiftSettings: approachable),
        .target(
            name: "BridgeShared",
            dependencies: ["BridgeCore", .product(name: "Automerge", package: "automerge-swift")],
            swiftSettings: approachable
        ),
        .executableTarget(name: "bridge-cli", dependencies: ["BridgeCore"], swiftSettings: mainActor),
        .executableTarget(
            name: "Bridge",
            dependencies: ["BridgeCore", "BridgeShared"],
            resources: [.copy("web")],
            swiftSettings: mainActor
        ),
        .testTarget(name: "BridgeCoreTests", dependencies: ["BridgeCore"], swiftSettings: approachable),
        .testTarget(name: "BridgeSharedTests", dependencies: ["BridgeShared", "BridgeCore"], swiftSettings: approachable),
    ]
)
