import AppKit
import UniformTypeIdentifiers

final class MainWindowController: NSWindowController, NSMenuItemValidation {

    let canvas = CanvasView()
    let inspector = InspectorView()
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

        canvas.onChange = { [weak self] in self?.markDirty() }
        canvas.onSelectionChange = { [weak self] in self?.reloadInspector() }
        reloadInspector()

        DispatchQueue.main.async { [weak self] in self?.pgZoomFit(nil) }
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    private func buildLayout(in root: NSView) {
        // Palette sidebar
        let palette = PaletteView()
        palette.onInsert = { [weak self] kind in self?.canvas.insertAtCenter(kind) }
        root.addSubview(palette)

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
            palette.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            palette.topAnchor.constraint(equalTo: root.topAnchor),
            palette.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            palette.widthAnchor.constraint(equalToConstant: 200),

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
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SVGExporter.documentSVG(canvas.document).write(to: url, atomically: true, encoding: .utf8)
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

    @objc func pgDelete(_ sender: Any?) { canvas.deleteSelection() }

    @objc func pgSelectAll(_ sender: Any?) { canvas.selectAllElements() }

    @objc func pgFront(_ sender: Any?) { canvas.bringToFront() }

    @objc func pgBack(_ sender: Any?) { canvas.sendToBack() }

    @objc func pgScrews(_ sender: Any?) { canvas.insertCornerScrews() }

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
        case #selector(pgUndo(_:)):
            return canvas.edits.canUndo
        case #selector(pgRedo(_:)):
            return canvas.edits.canRedo
        case #selector(pgDelete(_:)):
            guard !canvas.selection.isEmpty else { return false }
            // Only claim plain ⌫ when the canvas has focus, so typing in
            // inspector text fields is never hijacked.
            return window?.firstResponder === canvas
        case #selector(pgDuplicate(_:)), #selector(pgFront(_:)), #selector(pgBack(_:)):
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
