import AppKit

// Entry point.
//
//   PanelGenerator                     → launch the editor GUI
//   PanelGenerator --selftest [dir]    → headless smoke test (writes SVG+PNG)

let arguments = Array(CommandLine.arguments.dropFirst())

if let i = arguments.firstIndex(of: "--selftest") {
    let outDir = (i + 1 < arguments.count) ? arguments[i + 1] : NSTemporaryDirectory()
    Selftest.run(outDir: outDir)   // never returns
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.regular)
app.run()
