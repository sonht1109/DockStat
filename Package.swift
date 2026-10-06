// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DockStat",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "dockstat",
            path: "Sources/DockStat",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
