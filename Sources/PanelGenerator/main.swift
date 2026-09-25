import AppKit

// Entry point.
//
//   PanelGenerator                     → launch the editor GUI
//   PanelGenerator --selftest [dir]    → headless smoke test (writes SVG+PNG)
//   PanelGenerator --emit <doc> [dir]  → panel, component artwork and C++
//   PanelGenerator --compare <a> <b>   → do two forms of a panel agree?
//   PanelGenerator --icon <doc> <png>  → a panel as a square app icon
//   PanelGenerator --png <doc> <png> [scale]  → full panel artwork as a PNG
//   PanelGenerator --grid <doc> [png] [scale]  → print the active Serge grid's
//                                                 lines (px & mm); optionally
//                                                 render them over the panel

let arguments = Array(CommandLine.arguments.dropFirst())

if let i = arguments.firstIndex(of: "--grid") {
    guard i + 1 < arguments.count else {
        print("usage: PanelGenerator --grid <document.panelgen> [out.png] [scale]")
        fflush(stdout)
        exit(2)
    }
    do {
        let doc = try PanelDocument.load(
            from: URL(fileURLWithPath: (arguments[i + 1] as NSString).expandingTildeInPath))
        let l = SergeGrid.lines(for: doc)
        func mm(_ v: CGFloat) -> String { Geo.fmt(PanelMetrics.mm(v)) }
        print("GRID  \(doc.name) · \(doc.widthHP)HP \(doc.format.rawValue) (\(Int(doc.pixelSize.width))×\(Int(doc.pixelSize.height)) px)")
        print("  main rows (px): \(l.mainRows.map { Geo.fmt($0) })")
        print("  main rows (mm): \(l.mainRows.map(mm))")
        print("  half rows (px): \(l.halfRows.map { Geo.fmt($0) })"
              + (doc.sergeGridOuterHalfSteps ? "  [+outer half-step]" : ""))
        print("  half rows (mm): \(l.halfRows.map(mm))")
        print("  main cols (px): \(l.mainCols.map { Geo.fmt($0) })")
        print("  main cols (mm): \(l.mainCols.map(mm))")
        print("  half cols (px): \(l.halfCols.map { Geo.fmt($0) })")
        print("  half cols (mm): \(l.halfCols.map(mm))")
        let cl = CustomGrid.lines(for: doc)
        print("  custom grid: \(doc.customGridColumns) cols x \(doc.customGridRows) rows"
              + (doc.customGridHalfPositions ? " (+half positions)" : ""))
        print("  custom main cols (px): \(cl.mainCols.map { Geo.fmt($0) })")
        print("  custom main rows (px): \(cl.mainRows.map { Geo.fmt($0) })")
        print("  custom half cols (px): \(cl.halfCols.map { Geo.fmt($0) })")
        print("  custom half rows (px): \(cl.halfRows.map { Geo.fmt($0) })")
        print("  custom quarter cols (px): \(cl.quarterCols.map { Geo.fmt($0) })")
        print("  custom quarter rows (px): \(cl.quarterRows.map { Geo.fmt($0) })")
        if i + 2 < arguments.count {
            let scale = (i + 3 < arguments.count) ? CGFloat(Double(arguments[i + 3]) ?? 4) : 4
            let data = try PNGExporter.pngDataWithGrid(doc, scale: scale)
            let out = URL(fileURLWithPath: (arguments[i + 2] as NSString).expandingTildeInPath)
            try data.write(to: out)
            print("  overlay png → \(out.path) (\(data.count) bytes)")
        }
        fflush(stdout)
        exit(0)
    } catch {
        print("GRID FAILED: \(error.localizedDescription)")
        fflush(stdout)
        exit(1)
    }
}

if let i = arguments.firstIndex(of: "--png") {
    guard i + 2 < arguments.count else {
        print("usage: PanelGenerator --png <document.panelgen> <out.png> [scale]")
        fflush(stdout)
        exit(2)
    }
    let scale = (i + 3 < arguments.count) ? CGFloat(Double(arguments[i + 3]) ?? 4) : 4
    do {
        let doc = try PanelDocument.load(
            from: URL(fileURLWithPath: (arguments[i + 1] as NSString).expandingTildeInPath))
        let data = try PNGExporter.pngData(doc, scale: scale)
        let out = URL(fileURLWithPath: (arguments[i + 2] as NSString).expandingTildeInPath)
        try data.write(to: out)
        print("PNG OK  \(doc.name) · scale \(scale) → \(out.path) (\(data.count) bytes)")
        fflush(stdout)
        exit(0)
    } catch {
        print("PNG FAILED: \(error.localizedDescription)")
        fflush(stdout)
        exit(1)
    }
}

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
    // outDir is the first arg after the document that isn't itself a flag
    // (or that flag's own value) -- so `--emit doc.panelgen --theme light`
    // (no outDir given) still parses, rather than swallowing "--theme" as
    // the output directory.
    let outDir = (i + 2 < arguments.count && !arguments[i + 2].hasPrefix("--")) ? arguments[i + 2] : "."
    var theme = Emit.ThemeSelection.auto
    if let t = arguments.firstIndex(of: "--theme"), t + 1 < arguments.count {
        guard let parsed = Emit.ThemeSelection.parse(arguments[t + 1]) else {
            print("usage: --theme dark|light|both (got \"\(arguments[t + 1])\")")
            fflush(stdout)
            exit(2)
        }
        theme = parsed
    }
    Emit.run(documentPath: document, outDir: outDir, theme: theme)   // never returns
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
