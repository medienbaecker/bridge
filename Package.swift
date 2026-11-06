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
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.1.0"),
    ],
    targets: [
        .target(name: "BridgeCore", swiftSettings: approachable),
        .executableTarget(name: "bridge-cli", dependencies: ["BridgeCore"], swiftSettings: mainActor),
        .executableTarget(
            name: "Bridge",
            dependencies: ["BridgeCore", .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")],
            resources: [.copy("web")],
            swiftSettings: mainActor
        ),
        .testTarget(name: "BridgeCoreTests", dependencies: ["BridgeCore"], swiftSettings: approachable),
    ]
)
