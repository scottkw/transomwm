// swift-tools-version: 6.2
import PackageDescription

let macSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "Transom",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TransomModel", targets: ["TransomModel"]),
        .library(name: "TransomEngine", targets: ["TransomEngine"]),
        .library(name: "TransomMac", targets: ["TransomMac"]),
    ],
    dependencies: [
        // The only runtime dependency (STACK.md). Pinned exactly; Package.resolved pins the tag's commit (T-03-10).
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "3.1.0"),
    ],
    targets: [
        .target(name: "TransomModel"),
        .target(name: "TransomEngine", dependencies: ["TransomModel"]),
        .target(name: "TransomPrivate"),
        .target(
            name: "TransomMac",
            dependencies: ["TransomEngine", "TransomPrivate", .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")],
            swiftSettings: macSettings
        ),
        .executableTarget(name: "TransomApp", dependencies: ["TransomMac"], swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(name: "TransomFixtureApp", swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(name: "transom-dump", dependencies: ["TransomMac", "TransomEngine"], swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(name: "transom-cli", dependencies: ["TransomEngine"]),
        .executableTarget(name: "transom-zoom-spike", dependencies: ["TransomMac", "TransomEngine"], swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(name: "transom-gesture-spike", dependencies: ["TransomMac", "TransomPrivate", "TransomEngine"], swiftSettings: [.defaultIsolation(MainActor.self)]),
        .executableTarget(
            name: "transom-spaces-spike",
            dependencies: ["TransomMac", "TransomPrivate", "TransomEngine", .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .target(name: "TransomTestSupport", dependencies: ["TransomEngine"]),
        .testTarget(name: "TransomModelTests", dependencies: ["TransomModel"]),
        .testTarget(name: "TransomEngineTests", dependencies: ["TransomEngine", "TransomTestSupport"], exclude: ["Fixtures"]),
        .testTarget(
            name: "TransomMacTests",
            dependencies: ["TransomMac", "TransomPrivate", .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")]
        ),
        .testTarget(
            name: "TransomMacIntegrationTests",
            dependencies: ["TransomMac", "TransomPrivate", "TransomFixtureApp"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
