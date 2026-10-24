// swift-tools-version: 6.2
import PackageDescription

let macSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "Pane",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PaneModel", targets: ["PaneModel"]),
        .library(name: "PaneEngine", targets: ["PaneEngine"]),
        .library(name: "PaneMac", targets: ["PaneMac"]),
    ],
    targets: [
        .target(name: "PaneModel"),
        .target(name: "PaneEngine", dependencies: ["PaneModel"]),
        .target(name: "PanePrivate"),
        .target(name: "PaneMac", dependencies: ["PaneEngine", "PanePrivate"], swiftSettings: macSettings),
        .executableTarget(name: "PaneApp", dependencies: ["PaneMac"], swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(name: "PaneFixtureApp", swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "PaneModelTests", dependencies: ["PaneModel"]),
        .testTarget(
            name: "PaneMacIntegrationTests",
            dependencies: ["PaneMac", "PanePrivate", "PaneFixtureApp"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
