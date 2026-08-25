import AppKit
import UniformTypeIdentifiers

final class MainWindowController: NSWindowController, NSMenuItemValidation {

    let canvas = CanvasView()
    let inspector = InspectorView()
    private var layerList: LayerListView!
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

        let palette = PaletteView()
        palette.translatesAutoresizingMaskIntoConstraints = false
        palette.onInsert = { [weak self] kind, preset in
            self?.canvas.insertAtCenter(kind, preset: preset)
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
            doc.elements.append(contentsOf: outcome.elements)
            canvas.applyDocument(doc, name: "Import SVG")
            canvas.setSelection(options.asTemplate ? [] : Set(outcome.elements.map(\.id)))
            reloadInspector()
            report(outcome, from: url, resized: resize.state == .on)
        } catch {
            showError("Could not import that SVG", error)
        }
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
        }
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
    @objc func pgCopy(_ sender: Any?) { canvas.copySelection() }
    @objc func pgCut(_ sender: Any?) { canvas.cutSelection() }
    @objc func pgPaste(_ sender: Any?) { canvas.paste() }

    @objc func pgDelete(_ sender: Any?) { canvas.deleteSelection() }

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
        canvas.snapEnabled = true
        canvas.needsDisplay = true
    }

    @objc func pgDeselectAll(_ sender: Any?) { canvas.setSelection([]) }

    @objc func pgToggleSnap(_ sender: Any?) {
        canvas.snapEnabled.toggle()
        canvas.needsDisplay = true
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

        File ▸ Import SVG (⌘I) reads an existing panel — as a faint tracing
        template you draw over, or as editable artwork. See Docs/IMPORT.md
        for what survives the trip and what does not.

        File ▸ Export SVG / PNG writes Rack-compatible artwork
        (1 HP = 15 px · 3U = 380 px · 1U = 127 px).
        """
        alert.runModal()
    }

    // MARK: Menu validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(pgToggleSnap(_:)):
            menuItem.state = canvas.snapEnabled ? .on : .off
        case #selector(pgSetSnapStep(_:)):
            menuItem.state = Int((canvas.snapStep * 100).rounded()) == menuItem.tag ? .on : .off
        case #selector(pgDeselectAll(_:)):
            return !canvas.selection.isEmpty
        case #selector(pgUndo(_:)):
            return canvas.edits.canUndo
        case #selector(pgRedo(_:)):
            return canvas.edits.canRedo
        case #selector(pgDelete(_:)):
            guard !canvas.selection.isEmpty else { return false }
            // Only claim plain ⌫ when the canvas has focus, so typing in
            // inspector text fields is never hijacked.
            return window?.firstResponder === canvas
        case #selector(pgCopy(_:)), #selector(pgCut(_:)):
            // ⌘C / ⌘X keep their text-editing meaning inside inspector fields.
            return window?.firstResponder === canvas && !canvas.selection.isEmpty
        case #selector(pgPaste(_:)):
            return window?.firstResponder === canvas && canvas.canPaste
        case #selector(pgDuplicate(_:)), #selector(pgFront(_:)), #selector(pgBack(_:)),
             #selector(pgMakeWidget(_:)), #selector(pgLabelSelection(_:)):
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
