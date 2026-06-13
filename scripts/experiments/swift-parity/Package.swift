// swift-tools-version: 6.0
// Throwaway parity harness: runs BipboxCore.TopicDiscovery on the experiment's
// real vectors to compare against the Python reference (cluster.py).
import PackageDescription

let package = Package(
    name: "swift-parity",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(name: "parity", dependencies: [.product(name: "BipboxCore", package: "bipbox")])
    ]
)
