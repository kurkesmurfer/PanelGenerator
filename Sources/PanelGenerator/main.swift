import AppKit
import PanelKit

// Entry point.
//
//   PanelGenerator                     → launch the editor GUI
//   PanelGenerator --selftest [dir]    → headless smoke test (writes SVG+PNG)
//   PanelGenerator --emit <doc> [dir]  → panel, component artwork and C++
//   PanelGenerator --compare <a> <b>   → do two forms of a panel agree?
//   PanelGenerator --icon <doc> <png>  → a panel as a square app icon
//   PanelGenerator --png <doc> <png> [scale]  → full panel artwork as a PNG
//   PanelGenerator --import-check <svg|cpp|folder> [pngdir]  → import every SVG
//                                                 and module .cpp,
//                                                 report what came in and what
//                                                 was lost; optionally render it
//   PanelGenerator --import-module <cpp> <out.panelgen> [--no-artwork]
//                                              → a module's C++ (and the panel
//                                                it names) as a document, the
//                                                way Import Module Code does
//   PanelGenerator --grid <doc> [png] [scale]  → print the active Serge grid's
//                                                 lines (px & mm); optionally
//                                                 render them over the panel

let arguments = Array(CommandLine.arguments.dropFirst())

if let i = arguments.firstIndex(of: "--import-check") {
    guard i + 1 < arguments.count else {
        print("usage: PanelGenerator --import-check <file.svg|folder> [png-output-folder]")
        fflush(stdout)
        exit(2)
    }
    let root = URL(fileURLWithPath: (arguments[i + 1] as NSString).expandingTildeInPath)
        .resolvingSymlinksInPath()
    let pngDir = i + 2 < arguments.count
        ? URL(fileURLWithPath: (arguments[i + 2] as NSString).expandingTildeInPath) : nil
    var files: [URL] = []
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue {
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let u = walker?.nextObject() as? URL {
            let ext = u.pathExtension.lowercased()
            if ext == "svg" || ext == "cpp" { files.append(u.resolvingSymlinksInPath()) }
        }
        files.sort { $0.path < $1.path }
    } else {
        files = [root]
    }
    if let pngDir { try? FileManager.default.createDirectory(at: pngDir, withIntermediateDirectories: true) }
    var failed = 0
    for url in files {
        let rel = url.path.hasPrefix(root.path) && url.path != root.path
            ? String(url.path.dropFirst(root.path.count + 1)) : url.lastPathComponent
        if url.pathExtension.lowercased() == "cpp" {
            guard let source = try? String(contentsOf: url, encoding: .utf8),
                  source.contains("ModuleWidget") else { continue }
            let src = try? ModuleImport.sources(for: url)
            let headers = src?.headers ?? []
            let o = CppImport.outcome(from: source, headers: headers,
                widgetSize: ModuleImport.widgetSizer(texts: headers + [source], pluginRoot: src?.pluginRoot))
            var roles: [String: Int] = [:]
            for e in o.elements { roles[e.role.rawValue, default: 0] += 1 }
            let summary = roles.keys.sorted().map { "\(roles[$0]!) \($0)" }.joined(separator: ", ")
            print("CPP   \(rel): \(o.elements.count) elements (\(summary))"
                  + (o.moduleSlug.map { ", slug \($0)" } ?? "") + (o.panelResource.map { ", panel \($0)" } ?? ""))
            for w in o.warnings { print("      - \(w)") }
            continue
        }
        do {
            let o = try SVGImport.outcome(from: try Data(contentsOf: url))
            var kinds: [String: Int] = [:]
            for e in o.elements { kinds[e.kind.rawValue, default: 0] += 1 }
            let summary = kinds.keys.sorted().map { "\(kinds[$0]!) \($0)" }.joined(separator: ", ")
            print("OK    \(rel): \(o.widthHP)HP \(o.format.rawValue), \(o.elements.count) elements (\(summary))"
                  + (o.background.map { ", background \($0.hexString)" } ?? ""))
            for w in o.warnings { print("      - \(w)") }
            if let pngDir {
                var doc = PanelDocument()
                doc.widthHP = o.widthHP
                doc.format = o.format
                if let bg = o.background { doc.background = bg }
                doc.elements = o.elements
                let name = rel.replacingOccurrences(of: "/", with: "__") + ".png"
                try PNGExporter.pngData(doc, scale: 2).write(to: pngDir.appendingPathComponent(name))
            }
        } catch {
            failed += 1
            print("FAIL  \(rel): \(error.localizedDescription)")
        }
    }
    print("\(files.count) file\(files.count == 1 ? "" : "s"), \(failed) failed")
    fflush(stdout)
    exit(failed == 0 ? 0 : 1)
}

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
        let pl = PaperfaceGrid.lines(for: doc)
        print("  paperface (\(PaperfaceGrid.columnHP(for: doc)) HP columns):")
        print("    main rows (mm): \(pl.mainRows.map(mm))")
        print("    half rows (mm): \(pl.halfRows.map(mm))")
        print("    main cols (mm): \(pl.mainCols.map(mm))")
        print("    half cols (mm): \(pl.halfCols.map(mm))")
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

if let i = arguments.firstIndex(of: "--import-module") {
    guard i + 2 < arguments.count else {
        print("usage: PanelGenerator --import-module <module.cpp> <out.panelgen> [--no-artwork]")
        fflush(stdout)
        exit(2)
    }
    do {
        let url = URL(fileURLWithPath: (arguments[i + 1] as NSString).expandingTildeInPath)
        let out = URL(fileURLWithPath: (arguments[i + 2] as NSString).expandingTildeInPath)
        let read = try ModuleImport.read(url)
        var doc = PanelDocument()
        let report = ModuleImport.apply(read, includeArtwork: !arguments.contains("--no-artwork"), to: &doc)
        try doc.save(to: out)
        print("IMPORT OK  \(url.lastPathComponent): \(read.outcome.elements.count) from code, "
              + "\(doc.elements.count) in all, \(read.sources.headerURLs.count) headers"
              + (read.panelURL.map { ", panel \($0.lastPathComponent)" } ?? "") + " → \(out.path)")
        for h in read.sources.headerURLs { print("  header \(h.path)") }
        for line in report { print("  - \(line)") }
        fflush(stdout)
        exit(0)
    } catch {
        print("IMPORT FAILED: \(error.localizedDescription)")
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
