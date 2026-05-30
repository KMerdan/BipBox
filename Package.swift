// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Bipbox",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BipboxApp", targets: ["BipboxApp"]),
        .library(name: "BipboxCore", targets: ["BipboxCore"]),
        .library(name: "BipboxWorkspaceUI", targets: ["BipboxWorkspaceUI"]),
        .library(name: "BipboxMenuBarUI", targets: ["BipboxMenuBarUI"]),
        .library(name: "BipboxMacOSAdapters", targets: ["BipboxMacOSAdapters"]),
        .library(name: "BipboxPersistence", targets: ["BipboxPersistence"]),
        .library(name: "BipboxAI", targets: ["BipboxAI"]),
        .library(name: "BipboxAppSupport", targets: ["BipboxAppSupport"])
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
                "BipboxAI"
            ],
            exclude: ["Resources/Info.plist"]
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
                "BipboxCore",
                "BipboxMenuBarUI",
                "BipboxWorkspaceUI",
                "BipboxMacOSAdapters",
                "BipboxPersistence"
            ]
        )
    ]
)
