// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Bipbox",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BipboxApp", targets: ["BipboxApp"]),
        .executable(name: "bipbox-harness", targets: ["BipboxHarnessCLI"]),
        .library(name: "BipboxHarness", targets: ["BipboxHarness"]),
        .library(name: "BipboxCore", targets: ["BipboxCore"]),
        .library(name: "BipboxWorkspaceUI", targets: ["BipboxWorkspaceUI"]),
        .library(name: "BipboxMenuBarUI", targets: ["BipboxMenuBarUI"]),
        .library(name: "BipboxMacOSAdapters", targets: ["BipboxMacOSAdapters"]),
        .library(name: "BipboxPersistence", targets: ["BipboxPersistence"]),
        .library(name: "BipboxAI", targets: ["BipboxAI"]),
        .library(name: "BipboxAppSupport", targets: ["BipboxAppSupport"]),
        .library(name: "BipboxMLX", targets: ["BipboxMLX"])
    ],
    dependencies: [
        // MLX on-device embeddings (Apple Silicon, no server). Isolated to BipboxMLX,
        // which only BipboxApp links — keeps tests/harness/AI MLX-free & fast.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMajor(from: "3.31.3")),
        .package(url: "https://github.com/huggingface/swift-huggingface", .upToNextMinor(from: "0.9.0")),
        .package(url: "https://github.com/huggingface/swift-transformers", .upToNextMinor(from: "1.3.0"))
    ],
    targets: [
        .executableTarget(
            name: "BipboxApp",
            dependencies: [
                "BipboxAppSupport",
                "BipboxWorkspaceUI",
                "BipboxMenuBarUI",
                "BipboxMacOSAdapters",
                "BipboxPersistence",
                "BipboxAI",
                "BipboxMLX"
            ],
            exclude: ["Resources/Info.plist"]
        ),
        .target(
            name: "BipboxMLX",
            dependencies: [
                "BipboxCore",
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers")
            ]
        ),
        .target(
            name: "BipboxHarness",
            dependencies: [
                "BipboxAppSupport",
                "BipboxWorkspaceUI",
                "BipboxCore"
            ]
        ),
        .executableTarget(
            name: "BipboxHarnessCLI",
            dependencies: ["BipboxHarness", "BipboxWorkspaceUI", "BipboxCore"]
        ),
        .target(name: "BipboxCore"),
        .target(
            name: "BipboxWorkspaceUI",
            dependencies: ["BipboxCore"]
        ),
        .target(
            name: "BipboxMenuBarUI",
            dependencies: ["BipboxCore"]
        ),
        .target(
            name: "BipboxMacOSAdapters",
            dependencies: ["BipboxCore"]
        ),
        .target(
            name: "BipboxPersistence",
            dependencies: ["BipboxCore"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "BipboxAI",
            dependencies: ["BipboxCore"]
        ),
        .target(
            name: "BipboxAppSupport",
            dependencies: [
                "BipboxAI",
                "BipboxCore",
                "BipboxMacOSAdapters",
                "BipboxPersistence"
            ]
        ),
        .testTarget(
            name: "BipboxCoreTests",
            dependencies: [
                "BipboxAI",
                "BipboxAppSupport",
                "BipboxHarness",
                "BipboxCore",
                "BipboxMenuBarUI",
                "BipboxWorkspaceUI",
                "BipboxMacOSAdapters",
                "BipboxPersistence"
            ]
        )
    ]
)
