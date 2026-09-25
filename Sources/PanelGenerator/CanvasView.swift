import AppKit
import CoreGraphics
import PanelKit

/// The panel editing surface. Owns the live document during an editing session,
/// the undo stack and the selection; reports changes back via closures.
final class CanvasView: NSView {

    static let margin: CGFloat = 48

    // MARK: State

    var document = PanelDocument() {
        didSet {
            resizeToFitDocument()
            needsDisplay = true
            notifyChange()
        }
    }

    let edits = UndoManager()

    var selection: Set<UUID> = []
    var snapEnabled = true
    /// Grid step in panel pixels. 15 px is 1 HP (5.08 mm); the default is a
    /// quarter of that, fine enough not to fight hand placement but still a
    /// grid. Change it in View ▸ Snap Step.
    var snapStep: CGFloat = PanelMetrics.pixelsPerHP / 4

    /// Which snap system placement/movement uses. `.sergeGrid` is the
    /// default: it snaps element *centres* to Serge's non-uniform row/column
    /// grid (see `SergeGrid`). `.customGrid` snaps to a plain, editable N x M
    /// grid (see `CustomGrid`) for panels whose real layout doesn't follow
    /// Serge's own -- e.g. an imported module with a different column count.
    /// `.uniform` is the older single-step grid, still used verbatim for
    /// resize handles and arrow-key nudging in all three modes, since "snap
    /// to grid lines" isn't a coherent idea for a resize.
    enum SnapMode { case uniform, sergeGrid, customGrid }
    var snapMode: SnapMode = .sergeGrid
    /// Which theme variant the canvas currently draws -- editing preview
    /// only (View ▸ Theme); never persisted to the document itself. Defaults
    /// to `.dark`, matching every document's own untouched colours, so this
    /// has zero effect on a panel that hasn't opted into theming.
    var themePreview: ThemeVariant = .dark
    var zoom: CGFloat = 1 {
        didSet { zoom = min(max(zoom, 0.25), 8); resizeToFitDocument(); needsDisplay = true }
    }

    var onChange: (() -> Void)?
    var onSelectionChange: (() -> Void)?

    private var suppressNotifications = false
    var suppressUndoRegistration = false
    var lastUndoName: String?
    private var lastUndoTime = Date.distantPast

    enum Paste {
        static let elementType = NSPasteboard.PasteboardType("dev.peet.panelgenerator.element-kind")
        /// Marks a payload as a saved fragment rather than an element kind.
        /// Kinds are raw values of `ElementKind`, none of which contain a
        /// colon, so the two never collide.
        static let stampPrefix = "stamp:"
    }

    // MARK: Init / metrics

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    private func commonInit() {
        registerForDraggedTypes([Paste.elementType])
        resizeToFitDocument()
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// Where the panel's top-left corner sits inside the canvas.
    ///
    /// The canvas is never smaller than the scroll view's visible area, so the
    /// panel ends up centred in the window and every visible pixel belongs to
    /// this view. That is what lets a click anywhere outside the panel reach
    /// the canvas at all — previously the surrounding dead space belonged to
    /// the scroll view, which swallows clicks, and only the 48 pt margin was
    /// live.
    var contentOrigin: CGPoint {
        let s = document.pixelSize
        return CGPoint(x: max(Self.margin, (bounds.width  - s.width  * zoom) / 2),
                       y: max(Self.margin, (bounds.height - s.height * zoom) / 2))
    }

    func resizeToFitDocument() {
        let s = document.pixelSize
        var newSize = CGSize(width: s.width * zoom + Self.margin * 2,
                             height: s.height * zoom + Self.margin * 2)
        if let visible = enclosingScrollView?.contentView.bounds.size {
            newSize.width = max(newSize.width, visible.width)
            newSize.height = max(newSize.height, visible.height)
        }
        if frame.size != newSize {
            frame.size = newSize
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: nil)
        if let clip = enclosingScrollView?.contentView {
            clip.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(visibleAreaChanged),
                                                   name: NSView.frameDidChangeNotification, object: clip)
        }
        resizeToFitDocument()
    }

    @objc private func visibleAreaChanged() {
        resizeToFitDocument()
        needsDisplay = true
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// Convert a window event location into panel pixel coordinates.
    func panelPoint(from event: NSEvent) -> CGPoint {
        panelPoint(fromViewPoint: convert(event.locationInWindow, from: nil))
    }
    func panelPoint(fromWindowLocation loc: NSPoint) -> CGPoint {
        panelPoint(fromViewPoint: convert(loc, from: nil))
    }
    func panelPoint(fromViewPoint p: CGPoint) -> CGPoint {
        let o = contentOrigin
        return CGPoint(x: (p.x - o.x) / zoom, y: (p.y - o.y) / zoom)
    }

    func notifyChange() {
        guard !suppressNotifications else { return }
        onChange?()
    }

    // MARK: Mutation core

    func beginLoad() { suppressNotifications = true }
    func endLoad() {
        suppressNotifications = false
        selection = []
        edits.removeAllActions()
        resizeToFitDocument()
        needsDisplay = true
        onSelectionChange?()
    }

    /// Whole-document change — panel settings included — with undo support and
    /// the selection preserved. `apply(elements:name:)` covers element edits;
    /// this covers everything else (name, HP, format, background). Both
    /// coalesce on `name` within 0.6 s, so a continuously-firing control
    /// (colour well, slider) collapses into one undo step.
    func applyDocument(_ newDocument: PanelDocument, name: String) {
        if !suppressUndoRegistration {
            let now = Date()
            let coalesce = (name == lastUndoName && now.timeIntervalSince(lastUndoTime) < 0.6)
            if !coalesce {
                let old = document
                edits.registerUndo(withTarget: self) { target in
                    target.applyDocument(old, name: name)
                }
                lastUndoName = name
                lastUndoTime = now
            }
        }
        let keep = selection
        document = newDocument   // didSet: resize, redraw, notifyChange
        selection = keep.intersection(Set(newDocument.elements.map(\.id)))
        needsDisplay = true
    }

    func apply(elements newElements: [PanelElement], name: String) {
        if !suppressUndoRegistration {
            let now = Date()
            let coalesce = (name == lastUndoName && now.timeIntervalSince(lastUndoTime) < 0.6)
            if !coalesce {
                let old = document.elements
                edits.registerUndo(withTarget: self) { target in
                    target.apply(elements: old, name: name)
                }
                lastUndoName = name
                lastUndoTime = now
            }
        }
        document.elements = newElements
        needsDisplay = true
        notifyChange()
    }

    func mutateSelection(_ name: String, _ transform: (inout PanelElement) -> Void) {
        var els = document.elements
        for i in els.indices where selection.contains(els[i].id) {
            transform(&els[i])
        }
        apply(elements: els, name: name)
    }

    func insert(_ newElements: [PanelElement], name: String) {
        apply(elements: document.elements + newElements, name: name)
        setSelection(Set(newElements.map(\.id)))
    }

    // Stored state for CanvasView+Clipboard (extensions cannot hold stored properties).
    static let pasteType = NSPasteboard.PasteboardType("dev.peet.PanelGenerator.elements")
    var canPaste: Bool { !clipboardElements.isEmpty }

    // Stored state for CanvasView+Commands (extensions cannot hold stored properties).
    /// Stand-in element for a homogeneous multi-selection; nil for a mixed one.
    var uniformSelection: PanelElement? { document.uniformSelection(ids: selection) }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        let chars = event.charactersIgnoringModifiers ?? ""

        // Escape clears the selection wherever the pointer happens to be.
        if event.keyCode == 53 {
            setSelection([])
            return
        }

        // ⌫ (backspace) and ⌦ (forward delete) both delete the selection.
        if chars == "\u{7F}" || chars == "\u{F728}" || event.keyCode == 51 || event.keyCode == 117 {
            deleteSelection()
            return
        }

        // Arrow keys nudge the selection (⇧ nudges by the snap-grid step).
        let step: CGFloat = event.modifierFlags.contains(.shift) ? snapStep : 1
        let delta: CGVector
        switch chars {
        case "\u{F700}": delta = CGVector(dx: 0, dy: -step)  // up
        case "\u{F701}": delta = CGVector(dx: 0, dy: step)   // down
        case "\u{F702}": delta = CGVector(dx: -step, dy: 0)  // left
        case "\u{F703}": delta = CGVector(dx: step, dy: 0)   // right
        default:
            super.keyDown(with: event)
            return
        }
        guard !selection.isEmpty else { return }
        mutateSelection("Nudge") {
            $0.frame.origin.x += delta.dx
            $0.frame.origin.y += delta.dy
        }
    }

    // Stored state for CanvasView+Drawing (extensions cannot hold stored properties).
    var marqueeRect: CGRect?

    // Stored state for CanvasView+Handles (extensions cannot hold stored properties).
    var handleSize: CGFloat { 8 / zoom }
    var overlayHandleSize: CGFloat { 14 / zoom }
    var overlayHandleOffset: CGFloat { 20 / zoom }

    // Stored state for CanvasView+Mouse (extensions cannot hold stored properties).
    var dragMode: DragMode = .idle
    /// The element under the cursor when a move began. It is the one that lands
    /// on the grid; everything else keeps its offset from it.
    var moveAnchor: UUID?
    /// True from mouseDown until mouseUp. Views that care about the document's
    /// *shape* rather than its coordinates — the layer list — can skip work
    /// while this is set: a drag moves elements, it does not rename or reorder
    /// them, and `onChange` fires from the document's didSet on every frame.
    var isGestureActive = false
    var downPanelPoint = CGPoint.zero
    var didDrag = false
    let minSize: CGFloat = 6
    /// Screen pixels of travel before a rotate gesture engages at all.
    let rotateDeadZone: CGFloat = 3
    /// Degrees within which rotation collapses to exactly upright.
    let rotateSnapToZero: CGFloat = 0.25

}
