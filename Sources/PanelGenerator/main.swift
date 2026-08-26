import AppKit

// Entry point.
//
//   PanelGenerator                     → launch the editor GUI
//   PanelGenerator --selftest [dir]    → headless smoke test (writes SVG+PNG)
//   PanelGenerator --emit <doc> [dir]  → panel, component artwork and C++
//   PanelGenerator --compare <a> <b>   → do two forms of a panel agree?
//   PanelGenerator --icon <doc> <png>  → a panel as a square app icon

let arguments = Array(CommandLine.arguments.dropFirst())

if let i = arguments.firstIndex(of: "--compare") {
    guard i + 2 < arguments.count else {
        print("""
        usage: PanelGenerator --compare <a> <b> [--tolerance <mm>] [--no-labels]

        Each side may be a .panelgen document, a module's .cpp, or an SVG with a
        components layer. Components are matched by identifier and reported as
        moved, renamed, missing or added; exits non-zero if the two disagree.
        """)
        fflush(stdout)
        exit(2)
    }
    var tolerance: CGFloat = 0.01
    if let t = arguments.firstIndex(of: "--tolerance"), t + 1 < arguments.count,
       let v = Double(arguments[t + 1]) {
        tolerance = CGFloat(v)
    }
    Compare.run(arguments[i + 1], arguments[i + 2],
                tolerance: tolerance,
                labels: !arguments.contains("--no-labels"))   // never returns
}

if let i = arguments.firstIndex(of: "--icon") {
    // A panel makes a fitting icon for the thing that draws panels.
    guard i + 2 < arguments.count else {
        print("usage: PanelGenerator --icon <document.panelgen> <out.png> [size]")
        fflush(stdout)
        exit(2)
    }
    let size = (i + 3 < arguments.count) ? Int(arguments[i + 3]) ?? 1024 : 1024
    do {
        let doc = try PanelDocument.load(
            from: URL(fileURLWithPath: (arguments[i + 1] as NSString).expandingTildeInPath))
        let data = try IconExporter.pngData(doc, size: size)
        let out = URL(fileURLWithPath: (arguments[i + 2] as NSString).expandingTildeInPath)
        try data.write(to: out)
        print("ICON OK  \(doc.name) · \(size)×\(size) → \(out.path) (\(data.count) bytes)")
        fflush(stdout)
        exit(0)
    } catch {
        print("ICON FAILED: \(error.localizedDescription)")
        fflush(stdout)
        exit(1)
    }
}

if let i = arguments.firstIndex(of: "--emit") {
    let document = (i + 1 < arguments.count) ? arguments[i + 1] : ""
    let outDir = (i + 2 < arguments.count) ? arguments[i + 2] : "."
    Emit.run(documentPath: document, outDir: outDir)   // never returns
}

if let i = arguments.firstIndex(of: "--selftest") {
    let outDir = (i + 1 < arguments.count) ? arguments[i + 1] : NSTemporaryDirectory()
    Selftest.run(outDir: outDir)   // never returns
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.regular)
app.run()
