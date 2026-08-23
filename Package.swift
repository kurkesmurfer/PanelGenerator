// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PanelGenerator",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PanelGenerator",
            path: "Sources/PanelGenerator"
        )
    ]
)
