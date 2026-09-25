// swift-tools-version:5.9
import PackageDescription

// PanelKit holds the document model, rendering, import/export and code
// generation: everything that does not need a window. PanelGenerator is the
// AppKit editor and the command-line front end on top of it.
//
// Cross-target API uses Swift's `package` access level: visible to every
// target in this package, invisible outside it.
let package = Package(
    name: "PanelGenerator",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "PanelKit",
            path: "Sources/PanelKit"
        ),
        .executableTarget(
            name: "PanelGenerator",
            dependencies: ["PanelKit"],
            path: "Sources/PanelGenerator"
        ),
    ]
)
