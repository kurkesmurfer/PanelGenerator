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
        // The editing surface. Its gesture, handle and snapping state is
        // internal to this module; the rest of the editor sees only the
        // `package` API.
        .target(
            name: "PanelCanvas",
            dependencies: ["PanelKit"],
            path: "Sources/PanelCanvas"
        ),
        .executableTarget(
            name: "PanelGenerator",
            dependencies: ["PanelKit", "PanelCanvas"],
            path: "Sources/PanelGenerator"
        ),
        .testTarget(
            name: "PanelKitTests",
            dependencies: ["PanelKit"],
            path: "Tests/PanelKitTests"
        ),
    ]
)
