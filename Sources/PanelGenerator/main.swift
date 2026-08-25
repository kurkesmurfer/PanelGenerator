import AppKit

// Entry point.
//
//   PanelGenerator                     → launch the editor GUI
//   PanelGenerator --selftest [dir]    → headless smoke test (writes SVG+PNG)
//   PanelGenerator --emit <doc> [dir]  → panel, component artwork and C++

let arguments = Array(CommandLine.arguments.dropFirst())

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
