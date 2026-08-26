import AppKit

// Entry point.
//
//   PanelGenerator                     → launch the editor GUI
//   PanelGenerator --selftest [dir]    → headless smoke test (writes SVG+PNG)
//   PanelGenerator --emit <doc> [dir]  → panel, component artwork and C++
//   PanelGenerator --compare <a> <b>   → do two forms of a panel agree?

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
