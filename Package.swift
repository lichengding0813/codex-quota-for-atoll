// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CodexQuotaIsland",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(
            url: "https://github.com/Ebullioscopic/AtollExtensionKit.git",
            revision: "296562051f4ee8fec55aaca14782b21b8e63cafa"
        )
    ],
    targets: [
        .executableTarget(
            name: "CodexQuotaIsland",
            dependencies: [
                .product(name: "AtollExtensionKit", package: "AtollExtensionKit")
            ],
            path: "Sources/CodexQuotaIsland"
        ),
        .testTarget(
            name: "CodexQuotaIslandTests",
            dependencies: ["CodexQuotaIsland"],
            path: "Tests/CodexQuotaIslandTests"
        )
    ]
)
