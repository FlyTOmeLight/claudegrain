// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "claudegrain",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "claudegrain", targets: ["ClaudegrainApp"]),
        .executable(name: "claudegrain-spike", targets: ["ClaudegrainSpike"]),
        .executable(name: "claudegrain-preview", targets: ["ClaudegrainPreview"]),
        .library(name: "ClaudegrainCore", targets: ["ClaudegrainCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
    ],
    targets: [
        .executableTarget(
            name: "ClaudegrainApp",
            dependencies: ["ClaudegrainCore"],
            path: "Sources/ClaudegrainApp",
            exclude: ["Info.plist", "Claudegrain.entitlements"],
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("WidgetKit")]
        ),
        .executableTarget(
            name: "ClaudegrainSpike",
            dependencies: ["ClaudegrainCore"],
            path: "Sources/ClaudegrainSpike"
        ),
        .executableTarget(
            name: "ClaudegrainPreview",
            dependencies: ["ClaudegrainCore"],
            path: "Sources/ClaudegrainPreview"
        ),
        .target(
            name: "ClaudegrainCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/ClaudegrainCore"
        ),
        .testTarget(
            name: "ClaudegrainCoreTests",
            dependencies: ["ClaudegrainCore", "ClaudegrainApp"],
            path: "Tests/ClaudegrainCoreTests",
            resources: [.process("Fixtures")]
        ),
    ]
)
