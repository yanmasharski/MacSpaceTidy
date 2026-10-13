// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacSpaceTidy",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacSpaceTidyCore", targets: ["MacSpaceTidyCore"]),
        .executable(name: "mac-space-tidy", targets: ["mac-space-tidy"]),
    ],
    targets: [
        .target(
            name: "MacSpaceTidyCore",
            resources: [.copy("Resources/catalog.json")]
        ),
        .executableTarget(
            name: "mac-space-tidy",
            dependencies: ["MacSpaceTidyCore"]
        ),
        .executableTarget(
            name: "MacSpaceTidyApp",
            dependencies: ["MacSpaceTidyCore"]
        ),
        .testTarget(
            name: "MacSpaceTidyCoreTests",
            dependencies: ["MacSpaceTidyCore"]
        ),
    ]
)
