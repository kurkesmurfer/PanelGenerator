import AppKit
import UniformTypeIdentifiers
import PanelKit

final class MainWindowController: NSWindowController, NSMenuItemValidation {

    let canvas = CanvasView()
    let inspector = InspectorView()
    private var layerList: LayerListView!
    var palette: PaletteView!
    var scrollView: NSScrollView!

    var fileURL: URL?
    var isDirty = false
    var suppressDirty = false

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

    func reloadInspector() {
        inspector.rebuild(document: canvas.document, canvas: canvas)
    }

    func markDirty() {
        guard !suppressDirty else { return }
        if !isDirty {
            isDirty = true
            updateTitle()
        }
    }

    func updateTitle() {
        var t = documentName
        if let u = fileURL { t += " — " + u.lastPathComponent }
        if isDirty { t = "• " + t }
        window?.title = t
    }

    var documentName: String { canvas.document.name }

    // Stored state for MainWindowController+Edit (extensions cannot hold stored properties).
    /// How far from a control a label may sit and still be about it. Eight
    /// millimetres is wider than any panel puts a label from its knob and
    /// narrower than the gap to the next row.
    var labelReach: CGFloat { 8 / PanelMetrics.mmPerPixel }

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

    func showError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.runModal()
    }
}
