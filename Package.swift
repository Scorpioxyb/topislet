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
        .executable(name: "QishuiStateProbe", targets: ["QishuiStateProbe"])
    ],
    targets: [
        .executableTarget(name: "MacBookIsland"),
        .executableTarget(name: "QishuiProbe"),
        .executableTarget(name: "QishuiStateProbe"),
        .testTarget(
            name: "MacBookIslandTests",
            dependencies: ["MacBookIsland"]
        )
    ]
)
