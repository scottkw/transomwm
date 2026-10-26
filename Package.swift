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
    dependencies: [
        // The only runtime dependency (STACK.md). Pinned exactly; Package.resolved pins the tag's commit (T-03-10).
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.1.0"),
    ],
    targets: [
        .target(name: "PaneModel"),
        .target(name: "PaneEngine", dependencies: ["PaneModel"]),
        .target(name: "PanePrivate"),
        .target(
            name: "PaneMac",
            dependencies: ["PaneEngine", "PanePrivate", .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")],
            swiftSettings: macSettings
        ),
        .executableTarget(name: "PaneApp", dependencies: ["PaneMac"], swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(name: "PaneFixtureApp", swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(name: "pane-dump", dependencies: ["PaneMac", "PaneEngine"], swiftSettings: [.defaultIsolation(MainActor.self)]),
        .target(name: "PaneTestSupport", dependencies: ["PaneEngine"]),
        .testTarget(name: "PaneModelTests", dependencies: ["PaneModel"]),
        .testTarget(name: "PaneEngineTests", dependencies: ["PaneEngine", "PaneTestSupport"], exclude: ["Fixtures"]),
        .testTarget(
            name: "PaneMacTests",
            dependencies: ["PaneMac", "PanePrivate", .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")]
        ),
        .testTarget(
            name: "PaneMacIntegrationTests",
            dependencies: ["PaneMac", "PanePrivate", "PaneFixtureApp"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
