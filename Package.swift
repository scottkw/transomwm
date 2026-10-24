// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pane",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PaneModel", targets: ["PaneModel"]),
    ],
    targets: [
        .target(name: "PaneModel"),
        .testTarget(name: "PaneModelTests", dependencies: ["PaneModel"]),
    ],
    swiftLanguageModes: [.v6]
)
