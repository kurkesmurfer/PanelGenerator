import AppKit
import UniformTypeIdentifiers
import PanelKit

final class MainWindowController: NSWindowController, NSMenuItemValidation {

    let canvas = CanvasView()
    let inspector = InspectorView()
    private var layerList: LayerListView!
    private var palette: PaletteView!
    private var scrollView: NSScrollView!

    private(set) var fileURL: URL?
    private(set) var isDirty = false
    private var suppressDirty = false

    // MARK: Init & layout

    init() {
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "PanelGenerator"
        win.minSize = NSSize(width: 1040, height: 620)
        super.init(window: win)
        win.center()
        buildLayout(in: win.contentView!)

        canvas.onChange = { [weak self] in
            self?.markDirty()
            self?.layerList.rebuild()
        }
        canvas.onSelectionChange = { [weak self] in
            self?.reloadInspector()
            self?.layerList.rebuild()
        }
        reloadInspector()

        DispatchQueue.main.async { [weak self] in
            self?.pgZoomFit(nil)
            self?.layerList.rebuild()
        }
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    private func buildLayout(in root: NSView) {
        // Left sidebar: palette on top, layer list below.
        let sidebar = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidebar)

        palette = PaletteView()
        palette.translatesAutoresizingMaskIntoConstraints = false
        palette.onInsert = { [weak self] kind, preset in
            self?.canvas.insertAtCenter(kind, preset: preset)
        }
        palette.onInsertStamp = { [weak self] name in
            self?.canvas.insertStampAtCenter(named: name)
        }
        sidebar.addSubview(palette)

        layerList = LayerListView()
        layerList.translatesAutoresizingMaskIntoConstraints = false
        layerList.canvas = canvas
        sidebar.addSubview(layerList)

        // Canvas scroll area
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = ColorSpec.hex("#1C1C22").nsColor
        scrollView.documentView = canvas
        root.addSubview(scrollView)

        // Inspector sidebar
        let inspectorScroll = NSScrollView()
        inspectorScroll.translatesAutoresizingMaskIntoConstraints = false
        inspectorScroll.hasVerticalScroller = true
        inspectorScroll.drawsBackground = true
        inspectorScroll.backgroundColor = ColorSpec.hex("#2B2B33").nsColor
        inspector.frame = CGRect(x: 0, y: 0, width: 300, height: 600)
        inspector.translatesAutoresizingMaskIntoConstraints = false
        inspectorScroll.documentView = inspector
        root.addSubview(inspectorScroll)

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 200),

            palette.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            palette.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            palette.topAnchor.constraint(equalTo: sidebar.topAnchor),
            palette.bottomAnchor.constraint(equalTo: layerList.topAnchor, constant: -1),

            layerList.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            layerList.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            layerList.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            layerList.heightAnchor.constraint(equalToConstant: 240),

            inspectorScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            inspectorScroll.topAnchor.constraint(equalTo: root.topAnchor),
            inspectorScroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            inspectorScroll.widthAnchor.constraint(equalToConstant: 300),

            scrollView.leadingAnchor.constraint(equalTo: palette.trailingAnchor, constant: 1),
            scrollView.trailingAnchor.constraint(equalTo: inspectorScroll.leadingAnchor, constant: -1),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            inspector.widthAnchor.constraint(equalToConstant: 286),
        ])
    }

    private func reloadInspector() {
        inspector.rebuild(document: canvas.document, canvas: canvas)
    }

    private func markDirty() {
        guard !suppressDirty else { return }
        if !isDirty {
            isDirty = true
            updateTitle()
        }
    }

    private func updateTitle() {
        var t = documentName
        if let u = fileURL { t += " — " + u.lastPathComponent }
        if isDirty { t = "• " + t }
        window?.title = t
    }

    private var documentName: String { canvas.document.name }

    // MARK: Document lifecycle

    @objc func pgNew(_ sender: Any?) {
        guard confirmDiscardIfNeeded() else { return }
        loadIntoCanvas(PanelDocument(), url: nil)
    }

    @objc func pgOpen(_ sender: Any?) {
        guard confirmDiscardIfNeeded() else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: PanelDocument.fileExtension) ?? .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            loadIntoCanvas(try PanelDocument.load(from: url), url: url)
        } catch {
            showError("Could not open panel", error)
        }
    }

    // MARK: Import

    /// Read an existing panel SVG — someone else's module, or your own earlier
    /// artwork — either as a tracing template or as editable elements.
    @objc func pgImportSVG(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.svg]
        panel.message = "Import a panel SVG as a tracing template or as editable artwork."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let choice = NSAlert()
        choice.messageText = "Import \(url.lastPathComponent)"
        choice.informativeText = "A template is reference only: drawn faintly, not clickable on the canvas, "
            + "and never exported — trace over it and delete it when you are done. Imported artwork is "
            + "editable, but only rectangles and ellipses come back as parametric elements; everything "
            + "else arrives as a path you can move, scale and recolour but not reshape."
        choice.addButton(withTitle: "Import")
        choice.addButton(withTitle: "Cancel")

        let box = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 82))
        let mode = NSPopUpButton(frame: CGRect(x: 0, y: 56, width: 320, height: 24))
        mode.addItems(withTitles: ["As tracing template", "As editable artwork"])
        let components = NSButton(checkboxWithTitle: "Read a helper.py components layer, if present",
                                  target: nil, action: nil)
        components.state = .on
        components.frame = CGRect(x: 0, y: 30, width: 320, height: 20)
        let resize = NSButton(checkboxWithTitle: "Take the panel's size and background from the file",
                              target: nil, action: nil)
        resize.state = canvas.document.elements.isEmpty ? .on : .off
        resize.frame = CGRect(x: 0, y: 6, width: 320, height: 20)
        box.addSubview(mode); box.addSubview(components); box.addSubview(resize)
        choice.accessoryView = box
        guard choice.runModal() == .alertFirstButtonReturn else { return }

        var options = SVGImport.Options()
        options.asTemplate = mode.indexOfSelectedItem == 0
        options.bindComponents = components.state == .on
        options.adoptBackground = resize.state == .on

        do {
            let data = try Data(contentsOf: url)
            let outcome = try SVGImport.outcome(from: data, options: options)
            var doc = canvas.document
            if resize.state == .on {
                doc.widthHP = outcome.widthHP
                doc.format = outcome.format
                if let bg = outcome.background { doc.background = bg }
            }
            if !options.asTemplate, doc.name.isEmpty || doc.name == "Untitled" {
                // Name the document after the import too, when it has no name
                // of its own -- otherwise every import must be retitled by
                // hand. A re-imported PanelGenerator export recovers its
                // exact name from its own header comment; anything else
                // falls back to the file's name on disk.
                doc.name = outcome.suggestedName ?? url.deletingPathExtension().lastPathComponent
            }
            doc.elements.append(contentsOf: outcome.elements)
            canvas.applyDocument(doc, name: "Import SVG")
            canvas.setSelection(options.asTemplate ? [] : Set(outcome.elements.map(\.id)))
            reloadInspector()
            report(outcome, from: url, resized: resize.state == .on)
        } catch {
            showError("Could not import that SVG", error)
        }
    }

    /// Read a module's C++ and rebuild its components: positions, widget types
    /// and identifiers all at once. The panel SVG beside it supplies the
    /// artwork, which is why this offers to import it in the same pass.
    @objc func pgImportModuleCode(_ sender: Any?) {
        let open = NSOpenPanel()
        open.canChooseDirectories = false
        open.allowsMultipleSelection = false
        open.allowedContentTypes = [UTType(filenameExtension: "cpp") ?? .sourceCode,
                                    UTType(filenameExtension: "cc") ?? .sourceCode,
                                    UTType(filenameExtension: "hpp") ?? .sourceCode,
                                    .sourceCode]
        open.message = "Choose the source holding the ModuleWidget constructor."
        guard open.runModal() == .OK, let url = open.url else { return }

        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            // Constants are routinely declared in a sibling header — a panel
            // laid out on a named grid is unreadable without them.
            let siblings = (try? FileManager.default.contentsOfDirectory(
                at: url.deletingLastPathComponent(), includingPropertiesForKeys: [.fileSizeKey]))?
                .filter { ["h", "hpp", "hh"].contains($0.pathExtension.lowercased()) }
                .prefix(24) ?? []
            let headers = siblings.compactMap { try? String(contentsOf: $0, encoding: .utf8) }

            // Read once to learn which panel the widget sets, then again
            // knowing how big that panel is. Rack's own module template
            // positions its screws from box.size.x, and a module widget's box
            // is whatever setPanel gave it — so the second pass is what makes
            // the two right-hand screws of nearly every plugin readable.
            let first = CppImport.outcome(from: source, headers: headers)
            let panelURL = first.panelResource.flatMap { resolveResource($0, near: url) }
            let panelSize = panelURL
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap { SVGImport.panelSize(from: $0) }
            let outcome = panelSize == nil
                ? first
                : CppImport.outcome(from: source, headers: headers, panelSize: panelSize)

            // The plugin slug is not in the source — it lives in plugin.json,
            // beside it or one level up. It names the generated widget library
            // and its namespace, so importing without it produces a plugin
            // called MyPlugin.
            let plugin = pluginManifest(near: url)
            let answer = confirmModuleImport(outcome, source: url, panel: panelURL)
            guard answer.proceed else { return }
            let artworkURL = answer.includeArtwork ? panelURL : nil

            var doc = canvas.document
            var report = outcome.warnings

            // Artwork first, so the components land on top of it.
            if let artworkURL {
                do {
                    var options = SVGImport.Options()
                    options.bindComponents = false      // the C++ is the authority here
                    let art = try SVGImport.outcome(from: try Data(contentsOf: artworkURL), options: options)
                    doc.widthHP = art.widthHP
                    doc.format = art.format
                    if let bg = art.background { doc.background = bg }
                    doc.elements.append(contentsOf: art.elements)
                    report.append(contentsOf: art.warnings)
                } catch {
                    report.append("The panel \(artworkURL.lastPathComponent) could not be read: "
                        + error.localizedDescription)
                }
            }
            if let hp = outcome.widthHP { doc.widthHP = hp }
            if let plugin { doc.pluginSlug = plugin }
            if let slug = outcome.moduleSlug {
                doc.moduleSlug = slug
                // Name the document after the module too, when it has no name
                // of its own. Otherwise an emitted panel reports itself as
                // "Untitled" for the rest of its life.
                if doc.name.isEmpty || doc.name == "Untitled" { doc.name = slug }
            }
            doc.elements.append(contentsOf: outcome.elements)

            canvas.applyDocument(doc, name: "Import Module Code")
            canvas.setSelection(Set(outcome.elements.map(\.id)))
            reloadInspector()

            let done = NSAlert()
            let n = outcome.elements.count
            done.messageText = "Imported \(n) component\(n == 1 ? "" : "s")"
            done.informativeText = report.isEmpty
                ? "Everything in the file was understood."
                : report.joined(separator: "\n\n")
            done.runModal()
        } catch {
            showError("Could not read that source file", error)
        }
    }

    /// Confirm before overwriting, and say what was found — including the
    /// tallies, because "42 components" is the number you check against the
    /// module you are looking at.
    private func confirmModuleImport(_ outcome: CppImport.Outcome, source: URL,
                                     panel: URL?) -> (proceed: Bool, includeArtwork: Bool) {
        let params = outcome.elements.filter { $0.role == .param }.count
        let inputs = outcome.elements.filter { $0.role == .input }.count
        let outputs = outcome.elements.filter { $0.role == .output }.count
        let lights = outcome.elements.filter { $0.role == .light }.count

        let alert = NSAlert()
        alert.messageText = "Import \(outcome.elements.count) components from \(source.lastPathComponent)?"
        var lines = ["\(params) params · \(inputs) inputs · \(outputs) outputs · \(lights) lights"]
        if let slug = outcome.moduleSlug { lines.append("Module slug: \(slug)") }
        if let plugin = pluginManifest(near: source) {
            lines.append("Plugin slug: \(plugin), from plugin.json — it names the generated widget library.")
        }
        if panel == nil, let named = outcome.panelResource {
            lines.append("The source names \(named), which is not where this reader looked. "
                + "Import it separately with File ▸ Import SVG.")
        }
        if !canvas.document.elements.isEmpty {
            lines.append("This adds to the panel you have open rather than replacing it.")
        }
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")

        // Only offered when the artwork was actually found. Ticked by default:
        // components with no panel behind them are a list of coordinates, and
        // the point of reading the source is to get the module back whole.
        var artwork: NSButton? = nil
        if let panel {
            let check = NSButton(checkboxWithTitle: "Also import \(panel.lastPathComponent) as artwork",
                                 target: nil, action: nil)
            check.state = .on
            check.toolTip = "Untick if you have already imported the panel — otherwise you get it twice."
            check.frame = CGRect(x: 0, y: 0, width: 320, height: 20)
            alert.accessoryView = check
            artwork = check
        }

        let proceed = alert.runModal() == .alertFirstButtonReturn
        return (proceed, artwork?.state == .on)
    }

    /// The plugin's slug, from the plugin.json Rack requires every plugin to
    /// have. Looked for beside the source and one level up, the same two places
    /// the panel artwork is.
    private func pluginManifest(near source: URL) -> String? {
        let dir = source.deletingLastPathComponent()
        for candidate in [dir.appendingPathComponent("plugin.json"),
                          dir.deletingLastPathComponent().appendingPathComponent("plugin.json")] {
            guard let data = try? Data(contentsOf: candidate),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let slug = json["slug"] as? String, !slug.isEmpty else { continue }
            return slug
        }
        return nil
    }

    /// `res/Muse.svg` as written in the source, found on disk. Plugins put the
    /// source in the root or in src/, so both are worth a look.
    private func resolveResource(_ relative: String, near source: URL) -> URL? {
        let dir = source.deletingLastPathComponent()
        let candidates = [
            dir.appendingPathComponent(relative),
            dir.deletingLastPathComponent().appendingPathComponent(relative),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// What came in, and what did not. An importer that silently drops half a
    /// panel is worse than one that refuses: you would find out by noticing a
    /// hole in your own drawing a week later.
    private func report(_ outcome: SVGImport.Outcome, from url: URL, resized: Bool) {
        let alert = NSAlert()
        let count = outcome.elements.count
        alert.messageText = "Imported \(count) element\(count == 1 ? "" : "s")"
        var lines: [String] = []
        lines.append(String(format: "%@ measures %.0f × %.0f px (%.1f × %.1f mm) — %d HP %@.",
                            url.lastPathComponent,
                            outcome.sourceSize.width, outcome.sourceSize.height,
                            PanelMetrics.mm(outcome.sourceSize.width),
                            PanelMetrics.mm(outcome.sourceSize.height),
                            outcome.widthHP, outcome.format.rawValue))
        if !resized {
            lines.append("The panel kept its own size; the import may not line up with it.")
        }
        lines.append(contentsOf: outcome.warnings)
        alert.informativeText = lines.joined(separator: "\n\n")
        alert.runModal()
    }

    private func loadIntoCanvas(_ doc: PanelDocument, url: URL?) {
        suppressDirty = true
        canvas.beginLoad()
        canvas.document = doc
        canvas.endLoad()
        suppressDirty = false
        fileURL = url
        isDirty = false
        reloadInspector()
        updateTitle()
        pgZoomFit(nil)
    }

    @objc func pgSave(_ sender: Any?) {
        if let url = fileURL {
            save(to: url)
        } else {
            pgSaveAs(sender)
        }
    }

    @objc func pgSaveAs(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: PanelDocument.fileExtension) ?? .json]
        panel.nameFieldStringValue = sanitizedFileName + "." + PanelDocument.fileExtension
        guard panel.runModal() == .OK, let url = panel.url else { return }
        save(to: url)
    }

    private func save(to url: URL) {
        do {
            try canvas.document.save(to: url)
            fileURL = url
            isDirty = false
            updateTitle()
        } catch {
            showError("Could not save panel", error)
        }
    }

    private var sanitizedFileName: String {
        let bad = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return documentName.components(separatedBy: bad).joined(separator: "-")
    }

    // MARK: Export

    @objc func pgExportSVG(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.svg]
        panel.nameFieldStringValue = sanitizedFileName + ".svg"
        let componentCount = canvas.document.components.count
        panel.message = componentCount > 0
            ? "Writes the panel artwork plus a \"-components.svg\" positions file for helper.py (\(componentCount) component\(componentCount == 1 ? "" : "s"))."
            : "Nothing is bound as a component yet, so everything exports as artwork."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SVGExporter.documentSVG(canvas.document).write(to: url, atomically: true, encoding: .utf8)
            // Positions go in their own file: everything inside the panel SVG is
            // artwork to Rack, so the marker layer must not ship with it.
            if componentCount > 0 {
                let name = url.deletingPathExtension().lastPathComponent + "-components.svg"
                let sidecar = url.deletingLastPathComponent().appendingPathComponent(name)
                try SVGExporter.componentsSVG(canvas.document).write(to: sidecar, atomically: true, encoding: .utf8)
            }
        } catch {
            showError("Could not export SVG", error)
        }
    }

    @objc func pgExportPNG(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = sanitizedFileName + ".png"
        panel.message = "Exports at 4× resolution (\(Int(canvas.document.pixelSize.width * 4))×\(Int(canvas.document.pixelSize.height * 4)) px)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PNGExporter.pngData(canvas.document, scale: 4).write(to: url)
        } catch {
            showError("Could not export PNG", error)
        }
    }


    @objc func pgExportCode(_ sender: Any?) {
        let doc = canvas.document
        guard !doc.components.isEmpty else {
            let a = NSAlert()
            a.messageText = "Nothing is bound as a component yet."
            a.informativeText = "Give at least one element a Role other than Decoration in the "
                + "inspector. That is what tells PanelGenerator which elements Rack draws itself, "
                + "and those are the ones that turn into widget code."
            a.runModal()
            return
        }

        let customNames = Set(doc.components
            .filter { $0.widgetSource == .custom }
            .map(\.customWidgetName)
            .filter { !$0.isEmpty })

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "hpp") ?? .plainText]
        panel.nameFieldStringValue = CodeGen.moduleIdentifier(doc) + "_panel.hpp"
        panel.message = customNames.isEmpty
            ? "Writes the ID enums and the ModuleWidget constructor body."
            : "Writes the widget code plus a components/ folder with artwork for "
              + "\(customNames.count) custom widget\(customNames.count == 1 ? "" : "s")."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try CodeGen.panelHeader(doc).write(to: url, atomically: true, encoding: .utf8)
            guard !customNames.isEmpty else { return }

            let dir = url.deletingLastPathComponent().appendingPathComponent("components")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var written = Set<String>()
            for el in doc.components where el.widgetSource == .custom {
                let name = el.customWidgetName
                guard !name.isEmpty, written.insert(name).inserted else { continue }
                // A knob needs two files (static body + rotating indicator); a
                // switch needs one per position, of which we can supply the first.
                for file in CodeGen.componentFiles(for: el, in: doc) {
                    try SVGExporter.componentSVG(el, in: doc, layer: file.layer, units: doc.svgUnits)
                        .write(to: dir.appendingPathComponent(file.name),
                               atomically: true, encoding: .utf8)
                }
            }
        } catch {
            showError("Could not export widget code", error)
            return
        }

        presentCodeGenWarnings(CodeGen.warnings(doc), afterExport: true)
    }

    /// `CodeGen.warnings` already catches this document's own name -- two
    /// controls of the same role sharing an identifier -- and already
    /// resolves it (the second becomes NAME_2, and so on) so generated code
    /// always compiles. What it did not have, until now, was any way to
    /// reach the person editing the panel: the check only ever ran from the
    /// `--emit` CLI, printed to a terminal nobody watches while working in
    /// the app. Shown here instead, at the two moments it actually matters:
    /// on demand (File > Check Panel for Issues...) and right after
    /// exporting the widget code a coder agent is about to be handed.
    private func presentCodeGenWarnings(_ warns: [String], afterExport: Bool) {
        guard !warns.isEmpty else {
            guard !afterExport else { return }  // silence on an already-clean export
            let alert = NSAlert()
            alert.messageText = "No issues found"
            alert.informativeText = "Nothing here would trip up code generation."
            alert.runModal()
            return
        }
        let alert = NSAlert()
        alert.messageText = afterExport
            ? "Exported, but \(warns.count) issue\(warns.count == 1 ? "" : "s") found"
            : "\(warns.count) issue\(warns.count == 1 ? "" : "s") found"
        alert.informativeText = warns.map { "• \($0)" }.joined(separator: "\n\n")
        alert.runModal()
    }

    @objc func pgCheckPanel(_ sender: Any?) {
        presentCodeGenWarnings(CodeGen.warnings(canvas.document), afterExport: false)
    }

    // MARK: Edit commands

    @objc func pgUndo(_ sender: Any?) {
        canvas.edits.undo()
        reloadInspector()
        markDirty()
    }

    @objc func pgRedo(_ sender: Any?) {
        canvas.edits.redo()
        reloadInspector()
        markDirty()
    }

    @objc func pgDuplicate(_ sender: Any?) { canvas.duplicateSelection() }
    // Standard NSText-matching selector names, deliberately not pg-prefixed
    // and wired with a nil target (AppDelegate.swift) -- see the note above
    // validateMenuItem for why.
    @objc func copy(_ sender: Any?) { canvas.copySelection() }
    @objc func cut(_ sender: Any?) { canvas.cutSelection() }
    @objc func paste(_ sender: Any?) { canvas.paste() }

    @objc func delete(_ sender: Any?) { canvas.deleteSelection() }

    @objc func pgSelectAll(_ sender: Any?) { canvas.selectAllElements() }

    @objc func pgFront(_ sender: Any?) { canvas.bringToFront() }

    @objc func pgBack(_ sender: Any?) { canvas.sendToBack() }

    @objc func pgScrews(_ sender: Any?) { canvas.insertCornerScrews() }

    @objc func pgMakeWidget(_ sender: Any?) {
        guard !canvas.selection.isEmpty else { return }
        inspector.makeWidgetFromMenu()
    }

    @objc func pgLabelSelection(_ sender: Any?) {
        guard !canvas.selection.isEmpty else { return }
        inspector.labelSelectionFromMenu()
    }

    /// Turn the labels drawn on the panel into component identifiers.
    ///
    /// A label and an identifier are different fields — one is drawn, the other
    /// reaches the generated enum — and a panel can be fully labelled while
    /// every component is still unnamed. On a labelled panel the label is what
    /// you would have typed anyway.
    @objc func pgNameFromLabels(_ sender: Any?) {
        let result = canvas.nameFromLabels(within: labelReach)
        reloadInspector()
        let alert = NSAlert()
        alert.messageText = result.named == 0
            ? "No labels close enough to name anything"
            : "Named \(result.named) component\(result.named == 1 ? "" : "s") from their labels"
        alert.informativeText = result.skipped == 0
            ? "Every component in scope had a label beside it."
            : "\(result.skipped) had no label within \(Geo.fmt(PanelMetrics.mm(labelReach))) mm. "
                + "Label them, or set their Identifier by hand."
        alert.runModal()
    }

    /// Copy identifiers from another panel, matched on the label beside each
    /// control.
    ///
    /// What a redesign needs: the same module in a new layout has the same
    /// controls in different places, so position cannot pair them — but the
    /// label under a knob says what the knob is in both panels, and that is
    /// what the identifier records. It also means two documents never have to
    /// be open at once.
    @objc func pgAdoptIdentifiers(_ sender: Any?) {
        let open = NSOpenPanel()
        open.canChooseDirectories = false
        open.allowsMultipleSelection = false
        open.allowedContentTypes = [UTType(filenameExtension: PanelDocument.fileExtension) ?? .json,
                                    UTType(filenameExtension: "cpp") ?? .sourceCode]
        open.message = "Take identifiers from this panel or module source, matching by label."
        guard open.runModal() == .OK, let url = open.url else { return }

        do {
            let source: PanelDocument
            if url.pathExtension == PanelDocument.fileExtension {
                source = try PanelDocument.load(from: url)
            } else {
                // A module's source carries both halves too: the identifiers in
                // its create* calls and the labels in its helper calls.
                let text = try String(contentsOf: url, encoding: .utf8)
                let siblings = (try? FileManager.default.contentsOfDirectory(
                    at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil))?
                    .filter { ["h", "hpp", "hh"].contains($0.pathExtension.lowercased()) }
                    .prefix(24) ?? []
                var doc = PanelDocument()
                doc.elements = CppImport.outcome(
                    from: text,
                    headers: siblings.compactMap { try? String(contentsOf: $0, encoding: .utf8) }).elements
                source = doc
            }

            let result = canvas.adoptIdentifiers(from: source, within: labelReach)
            reloadInspector()

            let alert = NSAlert()
            let n = result.adopted.count
            alert.messageText = n == 0
                ? "Nothing matched"
                : "Adopted \(n) identifier\(n == 1 ? "" : "s") from \(url.lastPathComponent)"

            var lines: [String] = []
            // Every loose match is listed. A redesign renames as it goes, so
            // some of these are guesses — and a guess you cannot see is worse
            // than no guess at all.
            let loose = result.adopted.filter { $0.kind != .exact }
            if !loose.isEmpty {
                lines.append("Matched by abbreviation, worth checking:\n"
                    + loose.map { "   \($0.label) → \($0.identifier)" }.joined(separator: "\n"))
            }
            if !result.unmatched.isEmpty {
                lines.append("No match for:\n"
                    + result.unmatched.prefix(14).map { "   \($0)" }.joined(separator: "\n")
                    + (result.unmatched.count > 14 ? "\n   …" : ""))
                lines.append("Those keep the identifier they had. A control the old panel did not "
                    + "have is expected; a label that was reworded is not — rename it to match, "
                    + "or set Identifier by hand.")
            }
            if lines.isEmpty { lines.append("Every control matched exactly.") }
            alert.informativeText = lines.joined(separator: "\n\n")
            alert.runModal()
        } catch {
            showError("Could not read that panel", error)
        }
    }

    /// How far from a control a label may sit and still be about it. Eight
    /// millimetres is wider than any panel puts a label from its knob and
    /// narrower than the gap to the next row.
    private var labelReach: CGFloat { 8 / PanelMetrics.mmPerPixel }

    /// Bring a panel's contents back inside its edges after it has been
    /// narrowed. Offers the two operations that are defensible; anything
    /// cleverer is a design decision, and this is not the thing to make it.
    @objc func pgFitToPanel(_ sender: Any?) {
        let strays = canvas.document.strayComponents()

        let alert = NSAlert()
        alert.messageText = strays.isEmpty
            ? "Everything is already inside the panel"
            : "\(strays.count) component\(strays.count == 1 ? " sits" : "s sit") outside the "
              + "\(canvas.document.widthHP)HP panel"
        alert.informativeText = "Rack draws a component exactly where the code puts it, so one beyond "
            + "the module's edge cannot be seen or clicked — while still occupying a parameter.\n\n"
            + "Both moves are undoable, and neither changes any size: a component's size comes from "
            + "Rack's own artwork."
        alert.addButton(withTitle: "Fit")
        alert.addButton(withTitle: "Cancel")

        let box = NSView(frame: CGRect(x: 0, y: 0, width: 380, height: 78))
        let modes = PanelDocument.FitMode.allCases
        var buttons: [NSButton] = []
        for (i, mode) in modes.enumerated() {
            let b = NSButton(radioButtonWithTitle: mode.displayName, target: nil, action: nil)
            b.frame = CGRect(x: 0, y: 52 - CGFloat(i) * 24, width: 380, height: 20)
            b.state = i == 0 ? .on : .off
            box.addSubview(b)
            buttons.append(b)
        }
        let marginLabel = NSTextField(labelWithString: "Margin (px)")
        marginLabel.font = NSFont.systemFont(ofSize: 11)
        marginLabel.frame = CGRect(x: 0, y: 2, width: 80, height: 18)
        let margin = NSTextField(string: "6")
        margin.frame = CGRect(x: 84, y: 0, width: 56, height: 22)
        margin.toolTip = "Kept clear inside every edge. Rack's own panels leave room for the screws."
        box.addSubview(marginLabel)
        box.addSubview(margin)
        alert.accessoryView = box

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let picked = modes[buttons.firstIndex { $0.state == .on } ?? 0]
        let inset = CGFloat(Double(margin.stringValue) ?? 6)
        let moved = canvas.fitToPanel(picked, margin: max(0, inset))
        reloadInspector()

        let done = NSAlert()
        done.messageText = moved == 0 ? "Nothing needed moving" : "Moved \(moved) elements"
        done.informativeText = canvas.document.strayComponents().isEmpty
            ? "Every component is inside the panel."
            : "\(canvas.document.strayComponents().count) still sit outside — the panel may be too "
              + "narrow for the layout at any spacing. Widen it, or move those by hand."
        done.runModal()
    }

    @objc func pgBindPrimitives(_ sender: Any?) {
        let bound = canvas.bindPrimitives()
        reloadInspector()
        guard bound == 0 else { return }
        let alert = NSAlert()
        alert.messageText = "Nothing left to bind."
        alert.informativeText = "Every jack, knob, fader, button and LED already has a role. "
            + "Shapes, text and screws stay as artwork on purpose — set those by hand if you want them bound."
        alert.runModal()
    }

    // MARK: View commands

    @objc func pgZoomIn(_ sender: Any?)   { canvas.zoom *= 1.25 }
    @objc func pgZoomOut(_ sender: Any?)  { canvas.zoom /= 1.25 }
    @objc func pgZoomActual(_ sender: Any?) { canvas.zoom = 1 }

    @objc func pgZoomFit(_ sender: Any?) {
        guard let sv = scrollView else { return }
        let visible = sv.contentSize
        let size = canvas.document.pixelSize
        guard visible.width > 10, visible.height > 10 else { return }
        canvas.zoom = min(visible.width / size.width, visible.height / size.height) * 0.92
        sv.documentView?.scroll(NSPoint(x: 0, y: 0))
    }

    @objc func pgSetSnapStep(_ sender: Any?) {
        guard let mi = sender as? NSMenuItem else { return }
        canvas.snapStep = CGFloat(mi.tag) / 100
        canvas.snapMode = .uniform
        canvas.snapEnabled = true
        canvas.needsDisplay = true
    }

    /// Serge's non-uniform row/column grid (see `SergeGrid`) -- the default
    /// snap mode. Placement and movement snap element *centres* to it;
    /// resize handles and arrow-key nudging keep using the uniform step.
    @objc func pgSetSergeGrid(_ sender: Any?) {
        canvas.snapMode = .sergeGrid
        canvas.snapEnabled = true
        canvas.needsDisplay = true
    }

    /// Toggles `PanelDocument.sergeGridOuterHalfSteps`: one further half-step
    /// row beyond the top and bottom of Serge's standard 5-row grid, for
    /// real panels that push a row of LEDs/jacks that far out (e.g. the
    /// GTS's top LED row).
    ///
    /// Turning it ON also switches to Serge Grid and enables snapping, same
    /// as selecting "Serge Grid" itself -- the checkbox is meant to have an
    /// immediate, visible effect on the next drag, not just flip a flag that
    /// only matters if Serge Grid happens to already be the active mode.
    /// (Custom Grid's own half-positions checkbox gets this for free: it
    /// lives inside the "Custom Grid..." dialog, which already switches to
    /// Custom Grid on confirm. This one is a standalone menu item, so it has
    /// to do that switch itself.) Turning it OFF leaves the active mode
    /// alone -- there's no equivalent reason to switch *away* from Serge
    /// Grid just because this particular option was turned off.
    @objc func pgToggleSergeOuterHalfStep(_ sender: Any?) {
        let on = !canvas.document.sergeGridOuterHalfSteps
        canvas.mutateDocument(name: "Serge Grid Outer Half-Step") {
            $0.sergeGridOuterHalfSteps = on
        }
        if on {
            canvas.snapMode = .sergeGrid
            canvas.snapEnabled = true
        }
        canvas.needsDisplay = true
    }

    /// Switches what the canvas previews (View ▸ Theme) -- Dark always
    /// matches a document's own untouched colours; Light substitutes
    /// `PanelDocument.lightBackground`/`inkLight` wherever an element opted
    /// in via "Follows panel ink". Editing-only: never written to the
    /// document, and has no visible effect on a panel that isn't themed
    /// (`PanelDocument.isThemed`), since its light and dark colours are then
    /// identical by construction.
    @objc func pgSetThemePreview(_ sender: Any?) {
        guard let tag = (sender as? NSMenuItem)?.tag, let variant = ThemeVariant(rawValue: tag == 1 ? "light" : "dark") else { return }
        canvas.themePreview = variant
        canvas.needsDisplay = true
    }

    /// A plain, editable N x M grid (see `CustomGrid`) for panels whose real
    /// layout doesn't follow Serge's standardised one -- e.g. an imported
    /// module that genuinely has 5 columns, not Serge's 4. Always opens the
    /// dialog, even when custom grid is already the active mode, so the
    /// divisions stay easy to revisit rather than a one-time setup step.
    @objc func pgSetCustomGrid(_ sender: Any?) {
        let doc = canvas.document
        let alert = NSAlert()
        alert.messageText = "Custom Grid"
        alert.informativeText = "Divide the panel evenly into this many columns and rows. "
            + "Rows stay clear of the corner screws top and bottom. Placement and "
            + "movement will snap element centres to the intersections."
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")

        let box = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 106))
        let colsLabel = NSTextField(labelWithString: "Columns")
        colsLabel.frame = CGRect(x: 0, y: 84, width: 96, height: 18)
        let cols = NSTextField(string: String(max(1, doc.customGridColumns)))
        cols.frame = CGRect(x: 100, y: 82, width: 60, height: 22)
        let rowsLabel = NSTextField(labelWithString: "Rows")
        rowsLabel.frame = CGRect(x: 0, y: 56, width: 96, height: 18)
        let rows = NSTextField(string: String(max(1, doc.customGridRows)))
        rows.frame = CGRect(x: 100, y: 54, width: 60, height: 22)
        let half = NSButton(checkboxWithTitle: "Half positions (Serge-style)",
                            target: nil, action: nil)
        half.frame = CGRect(x: 0, y: 26, width: 240, height: 18)
        half.font = NSFont.systemFont(ofSize: 11)
        half.state = doc.customGridHalfPositions ? .on : .off
        half.toolTip = "Adds a half row between each pair of rows and half-lane columns "
            + "between each pair of columns, on the diagonal cross between four main "
            + "grid points -- Serge's own convention for where LEDs, switches and "
            + "jacks (never knobs) sit, generalised to this grid's own division count."
        let finer = NSButton(checkboxWithTitle: "Finer positions (quarter-step)",
                            target: nil, action: nil)
        finer.frame = CGRect(x: 0, y: 4, width: 240, height: 18)
        finer.font = NSFont.systemFont(ofSize: 11)
        finer.state = doc.customGridFinerPositions ? .on : .off
        finer.toolTip = "Adds a further pair of snap positions at 1/4 and 3/4 of every "
            + "cell, on every row and column -- unlike half positions, not tied to any "
            + "particular row or column kind. For layouts where two components flank a "
            + "half position instead of sharing it, e.g. a RISE/FALL pair's independent "
            + "EXPO switches either side of the half-lane column their shared CYCLE "
            + "switch already occupies."
        box.addSubview(colsLabel)
        box.addSubview(cols)
        box.addSubview(rowsLabel)
        box.addSubview(rows)
        box.addSubview(half)
        box.addSubview(finer)
        alert.accessoryView = box
        alert.window.initialFirstResponder = cols

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let n = max(1, Int(cols.stringValue) ?? doc.customGridColumns)
        let m = max(1, Int(rows.stringValue) ?? doc.customGridRows)
        let halfOn = half.state == .on
        let finerOn = finer.state == .on
        canvas.mutateDocument(name: "Custom Grid") {
            $0.customGridColumns = n
            $0.customGridRows = m
            $0.customGridHalfPositions = halfOn
            $0.customGridFinerPositions = finerOn
        }
        canvas.snapMode = .customGrid
        canvas.snapEnabled = true
        canvas.needsDisplay = true
    }

    @objc func pgDeselectAll(_ sender: Any?) { canvas.setSelection([]) }

    @objc func pgToggleSnap(_ sender: Any?) {
        canvas.snapEnabled.toggle()
        canvas.needsDisplay = true
    }

    // MARK: Stamps

    /// Save the selection to the palette.
    ///
    /// A house style is a handful of fragments repeated on every panel — a
    /// brand mark, a wordmark, a jack pair with its labels. They are the
    /// author's artwork, not the tool's, so the tool keeps them rather than
    /// shipping approximations of them.
    @objc func pgAddStamp(_ sender: Any?) {
        let selected = canvas.document.elements.filter { canvas.selection.contains($0.id) }
        guard !selected.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Add \(selected.count) element\(selected.count == 1 ? "" : "s") to the palette"
        alert.informativeText = """
        Saved fragments appear under Stamps and drop with fresh identity — no \
        component identifiers travel with them, so two panels never end up \
        sharing an enum name.
        """
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = suggestedStampName(for: selected)
        field.placeholderString = "Name"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        // Overwriting silently would lose work that only exists here.
        if StampLibrary.stamp(named: StampLibrary.fileName(from: name)) != nil {
            let confirm = NSAlert()
            confirm.messageText = "“\(name)” is already in the palette."
            confirm.informativeText = "Replace it?"
            confirm.addButton(withTitle: "Replace")
            confirm.addButton(withTitle: "Cancel")
            guard confirm.runModal() == .alertFirstButtonReturn else { return }
        }

        do {
            let stamp = try StampLibrary.save(selected, as: name)
            palette.rebuild()
            if stamp.name != name {
                let note = NSAlert()
                note.messageText = "Saved as “\(stamp.name)”"
                note.informativeText = "The name is also a filename, so a few characters were replaced."
                note.runModal()
            }
        } catch {
            let fail = NSAlert(error: error)
            fail.runModal()
        }
    }

    /// Text elements name themselves; anything else falls back to its kind.
    private func suggestedStampName(for elements: [PanelElement]) -> String {
        if let text = elements.first(where: { $0.kind == .text }) {
            let s = text.params.text.trimmingCharacters(in: .whitespaces)
            if !s.isEmpty { return s }
        }
        if elements.count == 1 { return elements[0].kind.displayName }
        return "Stamp"
    }

    /// Reveal the stamp folder so a fragment can be renamed, deleted or handed
    /// to someone else — they are plain JSON files, and a palette you cannot
    /// prune fills up with mistakes.
    @objc func pgRevealStamps(_ sender: Any?) {
        let dir = StampLibrary.directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc func pgReloadStamps(_ sender: Any?) {
        palette.rebuild()
    }

    /// Open the workflow manual in the default browser.
    ///
    /// A separate window rather than a sheet: the manual is something you keep
    /// beside the app while you work, and the browser already does windows,
    /// search and printing better than a bundled viewer would.
    @objc func pgWorkflowManual(_ sender: Any?) {
        guard let url = Self.manualURL() else {
            let alert = NSAlert()
            alert.messageText = "The workflow manual is not installed."
            alert.informativeText = """
            Docs/Workflow.html is missing beside the app. It lives in the \
            PanelGenerator source tree; running “make app” copies it into the \
            bundle.
            """
            alert.runModal()
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Bundle first — that is the copy an installed app has — then the source
    /// tree relative to the executable, which is where it is during development.
    static func manualURL() -> URL? {
        if let inBundle = Bundle.main.url(forResource: "Workflow", withExtension: "html") {
            return inBundle
        }
        let exe = Bundle.main.executableURL?.resolvingSymlinksInPath()
            ?? URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        var dir = exe.deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("Docs/Workflow.html")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            let resources = dir.appendingPathComponent("Resources/Workflow.html")
            if FileManager.default.fileExists(atPath: resources.path) { return resources }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    @objc func pgHelp(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "PanelGenerator — Quick Start"
        alert.informativeText = """
        Drag primitives and shapes from the left repo onto the panel.
        Double-click a repo item to drop it in the centre.

        • Click to select · Shift-click to multi-select · drag empty space to marquee
        • Drag handles to resize — small elements show corner handles only
        • Blue ↻ badge above the selection: drag to rotate (⇧ snaps 15°)
        • Orange ⇄ / ⇅ badges: click, or drag across the shape, to mirror (elbows)
        • ⌫ or ⌦ deletes the selection · arrow keys nudge (⇧ = grid step)
        • ⌘D duplicate
        • Snap-to-grid aligns to the HP grid (⇧⌘G toggles)
        • The Fill control uses the native macOS colour picker; the swatch
          bank below it is a curated LCARS / TNG palette.
        • Elbows + Ring Sectors + per-corner-radius boxes are your friends:
          that's how you get the Next Generation look.
        • Name the controls, then Edit ▸ Label Selection… (⌘L) labels all of
          them at once. The new labels stay selected, so Size in the inspector
          re-sizes the whole set in one go.
        • {ka} {ru} {te} … inside a label's text places an alien glyph inline.
        • Select part of a panel and Edit ▸ Add Selection to Palette… saves it
          as a Stamp — a brand mark, a wordmark, a jack pair with its labels.
          Stamps drop with fresh identity, so no identifier travels with them.

        Help ▸ Workflow Manual opens the full workflow in your browser.

        File ▸ Import SVG (⌘I) reads an existing panel — as a faint tracing
        template you draw over, or as editable artwork.
        File ▸ Import Module Code (⌥⌘I) reads a ModuleWidget constructor and
        rebuilds its components, artwork included. See Docs/IMPORT.md.

        File ▸ Export SVG / PNG writes Rack-compatible artwork
        (1 HP = 15 px · 3U = 380 px · 1U = 127 px).
        """
        alert.runModal()
    }

    // MARK: Menu validation

    /// Cut/Copy/Paste/Delete: a disabled menu item that still *claims* a key
    /// equivalent doesn't let the keystroke fall through to whatever has
    /// focus -- AppKit treats the key as consumed and just beeps. So an
    /// `isEditingText` guard here (an earlier version of this fix) was the
    /// wrong shape: it correctly detected real text editing, but disabling
    /// these items while a field editor was focused made the *beep* follow
    /// the text cursor instead of curing it -- confirmed live: opening the
    /// Edit menu by hand re-validates and reads enabled, yet the raw key
    /// still beeped, because the disabled-item interception happens before
    /// that revalidation is ever consulted for a real keystroke.
    ///
    /// The actual fix is standard Cocoa, not a focus check: these four menu
    /// items are wired with a *nil* target (AppDelegate.swift) and this
    /// controller's methods use the exact selector names AppKit's own
    /// NSText/NSTextView editing already implements (copy(_:), cut(_:),
    /// paste(_:), delete(_:)) instead of the pg-prefixed names every other
    /// custom action uses. A nil-targeted action is resolved fresh against
    /// the current first responder chain on every keystroke: while a field
    /// editor is first responder, AppKit finds *its* copy(_:) before ever
    /// reaching this controller (a window's windowController sits later in
    /// the chain, after its view hierarchy), so plain text editing keeps
    /// working automatically, validated by NSTextView's own
    /// enabled-when-something's-selected logic -- nothing here needs to
    /// know editing is happening at all. Once nothing text-related is
    /// first responder, resolution falls through to these methods and
    /// validateMenuItem below, exactly as for every other canvas-selection
    /// action in this switch.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(pgToggleSnap(_:)):
            menuItem.state = canvas.snapEnabled ? .on : .off
        case #selector(pgSetSnapStep(_:)):
            menuItem.state = (canvas.snapMode == .uniform
                              && Int((canvas.snapStep * 100).rounded()) == menuItem.tag) ? .on : .off
        case #selector(pgSetSergeGrid(_:)):
            menuItem.state = canvas.snapMode == .sergeGrid ? .on : .off
        case #selector(pgToggleSergeOuterHalfStep(_:)):
            menuItem.state = canvas.document.sergeGridOuterHalfSteps ? .on : .off
        case #selector(pgSetCustomGrid(_:)):
            menuItem.state = canvas.snapMode == .customGrid ? .on : .off
        case #selector(pgSetThemePreview(_:)):
            let wantsLight = menuItem.tag == 1
            menuItem.state = (canvas.themePreview == .light) == wantsLight ? .on : .off
        case #selector(pgDeselectAll(_:)):
            return !canvas.selection.isEmpty
        case #selector(pgUndo(_:)):
            return canvas.edits.canUndo
        case #selector(pgRedo(_:)):
            return canvas.edits.canRedo
        case #selector(delete(_:)):
            return !canvas.selection.isEmpty
        case #selector(copy(_:)), #selector(cut(_:)):
            return !canvas.selection.isEmpty
        case #selector(paste(_:)):
            return canvas.canPaste
        case #selector(pgDuplicate(_:)), #selector(pgFront(_:)), #selector(pgBack(_:)),
             #selector(pgMakeWidget(_:)), #selector(pgLabelSelection(_:)),
             #selector(pgAddStamp(_:)):
            return !canvas.selection.isEmpty
        default:
            break
        }
        return true
    }

    // MARK: Misc

    /// Returns true when it is OK to throw away current edits.
    func confirmDiscardIfNeeded() -> Bool {
        guard isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "The panel “\(documentName)” has changes."
        alert.informativeText = "Do you want to save them first?"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            pgSave(nil)
            return !isDirty
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    private func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.runModal()
    }
}
