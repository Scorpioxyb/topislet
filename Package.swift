// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacBookIsland",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "MacBookIsland", targets: ["MacBookIsland"]),
        .executable(name: "QishuiProbe", targets: ["QishuiProbe"]),
        .executable(name: "QishuiStateProbe", targets: ["QishuiStateProbe"]),
        .executable(name: "DailyUsageAnalyzer", targets: ["DailyUsageAnalyzer"])
    ],
    targets: [
        .executableTarget(
            name: "MacBookIsland",
            dependencies: ["AppleMusicBridge", "MusicUsageDiagnostics"]
        ),
        .target(
            name: "AppleMusicBridge",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ImageIO"),
                .linkedFramework("ScriptingBridge")
            ]
        ),
        .target(name: "MusicUsageDiagnostics"),
        .executableTarget(
            name: "DailyUsageAnalyzer",
            dependencies: ["MusicUsageDiagnostics"]
        ),
        .executableTarget(name: "QishuiProbe"),
        .executableTarget(name: "QishuiStateProbe"),
        .testTarget(
            name: "MacBookIslandTests",
            dependencies: [
                "MacBookIsland",
                "AppleMusicBridge",
                "MusicUsageDiagnostics"
            ]
        )
    ]
)
