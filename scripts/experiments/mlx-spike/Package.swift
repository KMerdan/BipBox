// swift-tools-version: 6.1
import PackageDescription

// Isolated spike: build the REAL MLXTextEmbedder (TextEmbedder conformance) +
// an argv-driven probe, before moving MLXTextEmbedder.swift into Bipbox.
let package = Package(
    name: "mlx-spike",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMajor(from: "3.31.3")),
        .package(url: "https://github.com/huggingface/swift-huggingface", .upToNextMinor(from: "0.9.0")),
        .package(url: "https://github.com/huggingface/swift-transformers", .upToNextMinor(from: "1.3.0")),
    ],
    targets: [
        .executableTarget(
            name: "mlx-spike",
            dependencies: [
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]
        )
    ]
)
