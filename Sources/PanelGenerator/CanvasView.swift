import AppKit
import CoreGraphics

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

    private(set) var selection: Set<UUID> = []
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
    private var suppressUndoRegistration = false
    private var lastUndoName: String?
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
    private func panelPoint(fromViewPoint p: CGPoint) -> CGPoint {
        let o = contentOrigin
        return CGPoint(x: (p.x - o.x) / zoom, y: (p.y - o.y) / zoom)
    }

    private func notifyChange() {
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

    // MARK: Copy / paste

    private static let pasteType = NSPasteboard.PasteboardType("dev.peet.PanelGenerator.elements")

    private var clipboardElements: [PanelElement] {
        get {
            guard let data = NSPasteboard.general.data(forType: Self.pasteType),
                  let els = try? JSONDecoder().decode([PanelElement].self, from: data) else { return [] }
            return els
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setData(data, forType: Self.pasteType)
        }
    }

    var canPaste: Bool { !clipboardElements.isEmpty }

    func copySelection() {
        let els = document.elements.filter { selection.contains($0.id) }
        guard !els.isEmpty else { return }
        clipboardElements = els
    }

    func cutSelection() {
        copySelection()
        deleteSelection()
    }

    func paste() {
        let els = clipboardElements
        guard !els.isEmpty else { return }
        var pasted: [PanelElement] = []
        for var e in els {
            e.id = UUID()
            e.x += PanelMetrics.pixelsPerHP
            e.y += PanelMetrics.pixelsPerHP
            pasted.append(e)
        }
        // Fresh group IDs here too, or pasting a group would select/move the
        // originals along with the paste.
        let remapped = withRemappedGroups(pasted)
        insert(remapped, name: "Paste")
        setSelection(Set(remapped.map(\.id)))
    }

    func insertAtCenter(_ kind: ElementKind, preset: String? = nil) {
        var el = kind.defaultElement(at: .zero)
        if let preset { el.applyPreset(preset) }
        let panelCenter = CGPoint(x: document.pixelSize.width / 2, y: document.pixelSize.height / 2)
        el.frame.origin = snappedOrigin(forCenter: panelCenter, size: CGSize(width: el.w, height: el.h))
        el.frame.origin.x = max(0, min(el.frame.origin.x, document.pixelSize.width - el.w))
        el.frame.origin.y = max(0, min(el.frame.origin.y, document.pixelSize.height - el.h))
        insert([el], name: "Add \(kind.displayName)")
    }

    // MARK: Stamps

    /// Drop a saved fragment centred on `point`, nudged back inside the panel
    /// if it would hang over an edge. Returns false only if the stamp is gone
    /// from disk since the palette was built.
    @discardableResult
    func insertStamp(named name: String, at point: CGPoint) -> Bool {
        guard let stamp = StampLibrary.stamp(named: name)?.resolved else { return false }
        let snapped = snappedCenter(point)
        var els = StampLibrary.instance(of: stamp, at: snapped)
        guard !els.isEmpty else { return false }

        // Shift the whole fragment as one, so a stamp never loses its internal
        // spacing to a clamp.
        var box = els[0].frame
        for el in els.dropFirst() { box = box.union(el.frame) }
        var dx: CGFloat = 0, dy: CGFloat = 0
        if box.maxX > document.pixelSize.width { dx = document.pixelSize.width - box.maxX }
        if box.minX + dx < 0 { dx = -box.minX }
        if box.maxY > document.pixelSize.height { dy = document.pixelSize.height - box.maxY }
        if box.minY + dy < 0 { dy = -box.minY }
        if dx != 0 || dy != 0 {
            for i in els.indices { els[i].x += dx; els[i].y += dy }
        }

        insert(els, name: "Add \(stamp.name)")
        return true
    }

    @discardableResult
    func insertStampAtCenter(named name: String) -> Bool {
        insertStamp(named: name,
                    at: CGPoint(x: document.pixelSize.width / 2,
                                y: document.pixelSize.height / 2))
    }

    // MARK: Selection & edit commands

    func setSelection(_ ids: Set<UUID>) {
        selection = ids
        needsDisplay = true
        onSelectionChange?()
    }

    /// Stand-in element for a homogeneous multi-selection; nil for a mixed one.
    var uniformSelection: PanelElement? { document.uniformSelection(ids: selection) }

    func selectionAgrees<T: Equatable>(_ keyPath: KeyPath<PanelElement, T>) -> Bool {
        document.selectionAgrees(keyPath, ids: selection)
    }

    var primaryElement: PanelElement? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return document.elements.first { $0.id == id }
    }

    func deleteSelection() {
        guard !selection.isEmpty else { return }
        apply(elements: document.elements.filter { !selection.contains($0.id) }, name: "Delete")
        setSelection([])
    }

    func duplicateSelection() {
        guard !selection.isEmpty else { return }
        let copies = document.elements
            .filter { selection.contains($0.id) }
            .map { el -> PanelElement in
                var c = el
                c.id = UUID()
                c.x += Geo.defaultSnap * 2
                c.y += Geo.defaultSnap * 2
                return c
            }
        // Fresh group IDs: a duplicated group must not stay glued to the original.
        insert(withRemappedGroups(copies), name: "Duplicate")
    }

    /// Undoable wrapper around `PanelDocument.bindPrimitives()`.
    @discardableResult
    func bindPrimitives() -> Int {
        var doc = document
        let bound = doc.bindPrimitives()
        guard bound > 0 else { return 0 }
        apply(elements: doc.elements, name: "Bind Primitives")
        return bound
    }

    func selectAllElements() {
        // Templates stay out: Select All followed by a nudge must not drag the
        // thing you are tracing out from under your drawing.
        setSelection(Set(document.elements.filter { $0.isTemplate != true }.map(\.id)))
    }

    func bringToFront() {
        guard !selection.isEmpty else { return }
        let front = document.elements.filter { selection.contains($0.id) }
        let rest = document.elements.filter { !selection.contains($0.id) }
        apply(elements: rest + front, name: "Reorder")
    }

    func sendToBack() {
        guard !selection.isEmpty else { return }
        let picked = document.elements.filter { selection.contains($0.id) }
        let rest = document.elements.filter { !selection.contains($0.id) }
        apply(elements: picked + rest, name: "Reorder")
    }

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

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Workspace backdrop
        ctx.setFillColor(ColorSpec.hex("#26262E").nsColor.cgColor)
        ctx.fill(bounds)

        ctx.saveGState()
        let origin = contentOrigin
        ctx.translateBy(x: origin.x, y: origin.y)
        ctx.scaleBy(x: zoom, y: zoom)

        // Panel shadow
        let panelRect = CGRect(origin: .zero, size: document.pixelSize)
        ctx.setShadow(offset: CGSize(width: 0, height: -3 / zoom), blur: 10 / zoom,
                      color: NSColor.black.withAlphaComponent(0.55).cgColor)
        ctx.setFillColor(document.paper(for: themePreview).nsColor.cgColor)
        ctx.fill(panelRect.insetBy(dx: -1, dy: -1).offsetBy(dx: 0, dy: 0))
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        Renderer.drawBackground(document, in: ctx, variant: themePreview)
        drawGrid(in: ctx)
        if snapEnabled && snapMode == .sergeGrid { drawSergeGrid(in: ctx) }
        if snapEnabled && snapMode == .customGrid { drawCustomGrid(in: ctx) }

        for el in document.elements where el.isHidden != true {
            // A tracing template is drawn faintly and behind your own work in
            // spirit — it is reference, not artwork. It is still visible enough
            // to trace, and the layer list is where you select or delete it.
            if el.isTemplate == true {
                ctx.saveGState()
                ctx.setAlpha(0.35)
                Renderer.draw(el, in: ctx, doc: document, variant: themePreview)
                ctx.restoreGState()
            } else {
                Renderer.draw(el, in: ctx, doc: document, variant: themePreview)
            }
        }

        drawSelectionOverlay(in: ctx)
        drawMarqueeOverlay(in: ctx)

        ctx.restoreGState()
    }

    private func drawGrid(in ctx: CGContext) {
        let size = document.pixelSize
        let minor = PanelMetrics.pixelsPerHP
        ctx.saveGState()
        ctx.clip(to: CGRect(origin: .zero, size: size))

        func lines(step: CGFloat, alpha: CGFloat) {
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(alpha).cgColor)
            ctx.setLineWidth(1 / zoom)
            var x: CGFloat = step
            while x < size.width - 0.01 {
                ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = step
            while y < size.height - 0.01 {
                ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            ctx.strokePath()
        }
        lines(step: minor, alpha: 0.05)
        lines(step: minor * 4, alpha: 0.09)
        ctx.restoreGState()
    }

    /// Visual guide for the active Serge grid: main row/main column
    /// intersections as solid dots (knob positions), every other
    /// combination -- main row x half-lane column, half row x main
    /// column, half row x half-lane column -- as smaller, dimmer dots (the
    /// LED/switch/jack positions, including the "parallel slot" a
    /// half-lane column offers on a main row -- confirmed against the real
    /// GTS panel, where status LEDs sit at half-lane column x's but at the
    /// full height of the main row 1 jacks either side of them).
    private func drawSergeGrid(in ctx: CGContext) {
        let l = SergeGrid.lines(for: document)
        guard !l.mainRows.isEmpty || !l.halfRows.isEmpty else { return }
        ctx.saveGState()
        ctx.clip(to: CGRect(origin: .zero, size: document.pixelSize))

        func dots(rows: [CGFloat], cols: [CGFloat], radius: CGFloat, alpha: CGFloat) {
            guard !rows.isEmpty, !cols.isEmpty else { return }
            ctx.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
            for y in rows {
                for x in cols {
                    ctx.fillEllipse(in: CGRect(x: x - radius, y: y - radius,
                                               width: radius * 2, height: radius * 2))
                }
            }
        }
        dots(rows: l.mainRows, cols: l.mainCols, radius: 2.2 / zoom, alpha: 0.35)
        dots(rows: l.mainRows, cols: l.halfCols, radius: 1.5 / zoom, alpha: 0.22)
        dots(rows: l.halfRows, cols: l.mainCols, radius: 1.5 / zoom, alpha: 0.22)
        dots(rows: l.halfRows, cols: l.halfCols, radius: 1.5 / zoom, alpha: 0.22)
        ctx.restoreGState()
    }

    /// Visual guide for the active custom grid: a dot at every column x row
    /// intersection of the panel's own configured N x M divisions, plus (if
    /// Serge-style half positions are on) dimmer dots at the half-row/
    /// half-lane crossings -- same two-tier treatment as `drawSergeGrid`.
    private func drawCustomGrid(in ctx: CGContext) {
        let l = CustomGrid.lines(for: document)
        guard !l.mainCols.isEmpty, !l.mainRows.isEmpty else { return }
        ctx.saveGState()
        ctx.clip(to: CGRect(origin: .zero, size: document.pixelSize))

        func dots(rows: [CGFloat], cols: [CGFloat], radius: CGFloat, alpha: CGFloat) {
            guard !rows.isEmpty, !cols.isEmpty else { return }
            ctx.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
            for y in rows {
                for x in cols {
                    ctx.fillEllipse(in: CGRect(x: x - radius, y: y - radius,
                                               width: radius * 2, height: radius * 2))
                }
            }
        }
        dots(rows: l.mainRows, cols: l.mainCols, radius: 2.2 / zoom, alpha: 0.35)
        dots(rows: l.halfRows, cols: l.halfCols, radius: 1.5 / zoom, alpha: 0.22)
        // Quarter tier is uncorrelated (available on every row/column), so
        // draw it as its own faint overlay rather than a diagonal subset.
        let allRows = l.mainRows + l.halfRows + l.quarterRows
        let allCols = l.mainCols + l.halfCols
        dots(rows: allRows, cols: l.quarterCols, radius: 1.1 / zoom, alpha: 0.14)
        dots(rows: l.quarterRows, cols: allCols, radius: 1.1 / zoom, alpha: 0.14)
        ctx.restoreGState()
    }

    private func transformedPath(for el: PanelElement) -> CGPath {
        guard el.rotation != 0 else { return CGPath(rect: el.frame, transform: nil) }
        var t = CGAffineTransform(translationX: el.center.x, y: el.center.y)
        t = t.rotated(by: Geo.deg2rad(el.rotation))
        t = t.translatedBy(x: -el.center.x, y: -el.center.y)
        return CGPath(rect: el.frame, transform: &t)
    }

    private func drawSelectionOverlay(in ctx: CGContext) {
        // Multi-selection: group bounds + corner handles + rotate badge.
        if selection.count > 1, let b = selectionBounds {
            ctx.setStrokeColor(ColorSpec.hex("#4FC3F7").nsColor.cgColor)
            ctx.setLineWidth(1 / zoom)
            ctx.stroke(b)
            for (dir, r) in activeHandles(for: b)
            where dir == .nw || dir == .ne || dir == .sw || dir == .se {
                ctx.setFillColor(NSColor.white.cgColor)
                let hr = r.insetBy(dx: -handleSize / 2, dy: -handleSize / 2)
                ctx.fill(hr)
                ctx.setStrokeColor(NSColor.black.cgColor)
                ctx.stroke(hr)
            }
            drawOverlayBadge(ctx, at: CGPoint(x: b.midX, y: b.minY - overlayHandleOffset),
                             glyph: "↻", color: ColorSpec.hex("#4FC3F7"))
        }
        let ids = selection
        guard !ids.isEmpty else { return }

        for el in document.elements where el.isHidden != true && ids.contains(el.id) {
            ctx.saveGState()
            ctx.addPath(transformedPath(for: el))
            ctx.setStrokeColor(ColorSpec.hex("#4FC3F7").nsColor.cgColor)
            ctx.setLineWidth(1.2 / zoom)
            ctx.setLineDash(phase: 0, lengths: [4 / zoom, 3 / zoom])
            ctx.strokePath()
            ctx.restoreGState()
        }

        // Resize handles, single-selection. Drawn at the frame's own
        // (unrotated) corners, then rotated onto the screen around the
        // element's centre so they still land on the visible, tilted
        // bounding box -- resizing along a rotated element's own axes only
        // reads correctly if its handles are where the element visibly is.
        if let p = primaryElement {
            let hs = handleSize
            for (_, r) in activeHandles(for: p.frame) {
                let mid = CGPoint(x: r.midX, y: r.midY)
                let c = p.rotation == 0 ? mid : Geo.rotate(mid, around: p.center, degrees: p.rotation)
                let hr = CGRect(x: c.x - hs / 2, y: c.y - hs / 2, width: hs, height: hs)
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(hr)
                ctx.setStrokeColor(NSColor.black.cgColor)
                ctx.setLineWidth(1 / zoom)
                ctx.stroke(hr)
            }
        }

        // Rotation + mirror badges (single selection).
        if let p = primaryElement {
            if let rp = rotateHandlePoint {
                ctx.setStrokeColor(ColorSpec.hex("#4FC3F7").nsColor.cgColor)
                ctx.setLineWidth(1.2 / zoom)
                ctx.move(to: CGPoint(x: p.frame.midX, y: p.frame.minY))
                ctx.addLine(to: rp)
                ctx.strokePath()
                drawOverlayBadge(ctx, at: rp, glyph: "↻", color: ColorSpec.hex("#4FC3F7"))
            }
            if let m = mirrorHandlePoints {
                drawOverlayBadge(ctx, at: m.x, glyph: "⇄", color: ColorSpec.hex("#FFB74D"))
                drawOverlayBadge(ctx, at: m.y, glyph: "⇅", color: ColorSpec.hex("#FFB74D"))
            }
        }
    }

    private func drawOverlayBadge(_ ctx: CGContext, at c: CGPoint, glyph: String, color: ColorSpec) {
        let r = badgeRect(at: c)
        ctx.setFillColor(color.nsColor.cgColor)
        ctx.fillEllipse(in: r)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        ctx.setLineWidth(1 / zoom)
        ctx.strokeEllipse(in: r)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 8), .foregroundColor: NSColor.black]
        let size = (glyph as NSString).size(withAttributes: attrs)
        (glyph as NSString).draw(at: CGPoint(x: c.x - size.width / 2, y: c.y - size.height / 2),
                                 withAttributes: attrs)
    }

    private var marqueeRect: CGRect?
    private func drawMarqueeOverlay(in ctx: CGContext) {
        guard let m = marqueeRect else { return }
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.08).cgColor)
        ctx.fill(m)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(1 / zoom)
        ctx.setLineDash(phase: 0, lengths: [3 / zoom, 3 / zoom])
        ctx.stroke(m)
    }

    // MARK: Handles

    enum HandleDir: String { case nw, n, ne, e, se, s, sw, w }

    private var handleSize: CGFloat { 8 / zoom }

    private func handleRects(for f: CGRect) -> [(HandleDir, CGRect)] {
        let hs = handleSize
        let pts: [(HandleDir, CGPoint)] = [
            (.nw, CGPoint(x: f.minX, y: f.minY)), (.n, CGPoint(x: f.midX, y: f.minY)),
            (.ne, CGPoint(x: f.maxX, y: f.minY)), (.e, CGPoint(x: f.maxX, y: f.midY)),
            (.se, CGPoint(x: f.maxX, y: f.maxY)), (.s, CGPoint(x: f.midX, y: f.maxY)),
            (.sw, CGPoint(x: f.minX, y: f.maxY)), (.w, CGPoint(x: f.minX, y: f.midY)),
        ]
        return pts.map { ($0.0, CGRect(x: $0.1.x - hs / 2, y: $0.1.y - hs / 2, width: hs, height: hs)) }
    }

    /// Handles that are actually usable for this frame. Edge-mid handles need
    /// perpendicular room — otherwise they carpet small elements (sliders!)
    /// and every grab turns into a resize instead of a move.
    private func activeHandles(for f: CGRect) -> [(HandleDir, CGRect)] {
        let hs = handleSize
        return handleRects(for: f).filter { (dir, _) in
            switch dir {
            case .nw, .ne, .se, .sw: return f.width >= hs * 2 || f.height >= hs * 2
            case .e, .w:             return f.height >= hs * 4
            case .n, .s:             return f.width  >= hs * 4
            }
        }
    }

    private func handle(at p: CGPoint) -> HandleDir? {
        guard let prim = primaryElement else { return nil }
        let local = toLocal(p, rotation: prim.rotation, center: prim.center)
        for (dir, r) in activeHandles(for: prim.frame) where r.contains(local) {
            return dir
        }
        return nil
    }

    /// Un-rotate a screen/panel point into an element's own local (unrotated)
    /// space -- the space its `frame` (x/y/w/h) is defined in. `rotation` is
    /// applied only at draw time (see `transformedPath`/`Renderer.applyRotation`),
    /// so hit-testing and resize math against the frame need the inverse of
    /// that same transform first.
    private func toLocal(_ p: CGPoint, rotation: CGFloat, center: CGPoint) -> CGPoint {
        rotation == 0 ? p : Geo.rotate(p, around: center, degrees: -rotation)
    }

    // MARK: Rotation & mirror overlay handles

    private var overlayHandleSize: CGFloat { 14 / zoom }
    private var overlayHandleOffset: CGFloat { 20 / zoom }

    private var rotateHandlePoint: CGPoint? {
        guard let f = primaryElement?.frame else { return nil }
        return CGPoint(x: f.midX, y: f.minY - overlayHandleOffset)
    }

    /// Mirror handles only for kinds whose renderer honours flipX / flipY
    /// (elbow, swirl).
    private var mirrorHandlePoints: (x: CGPoint, y: CGPoint)? {
        guard let el = primaryElement, el.kind == .elbow || el.kind == .swirl else { return nil }
        let f = el.frame
        return (CGPoint(x: f.minX - overlayHandleOffset, y: f.midY),
                CGPoint(x: f.midX, y: f.maxY + overlayHandleOffset))
    }

    private func badgeRect(at c: CGPoint) -> CGRect {
        CGRect(x: c.x - overlayHandleSize / 2, y: c.y - overlayHandleSize / 2,
               width: overlayHandleSize, height: overlayHandleSize)
    }

    private func overlayHandle(at p: CGPoint) -> OverlayHandle? {
        guard primaryElement != nil else { return nil }
        if let rp = rotateHandlePoint, badgeRect(at: rp).contains(p) { return .rotate }
        if let m = mirrorHandlePoints {
            if badgeRect(at: m.x).contains(p) { return .mirrorX }
            if badgeRect(at: m.y).contains(p) { return .mirrorY }
        }
        return nil
    }

    // MARK: Mouse interaction

    private enum DragMode {
        case idle
        case moving(origFrames: [UUID: CGRect])
        case resizing(dir: HandleDir, orig: CGRect, rotation: CGFloat, center: CGPoint)
        case rotating(origRotation: CGFloat, center: CGPoint, startAngle: CGFloat)
        case mirroring(axis: MirrorAxis, orig: Bool)
        case groupResizing(orig: CGRect, origFrames: [UUID: CGRect])
        case groupRotating(center: CGPoint, startAngle: CGFloat, origFrames: [UUID: CGRect], origRotations: [UUID: CGFloat])
        case marquee(start: CGPoint, baseSelection: Set<UUID>)
    }

    /// Mirror axis controlled by an overlay handle.
    enum MirrorAxis { case x, y }
    private enum OverlayHandle { case rotate, mirrorX, mirrorY }

    private var dragMode: DragMode = .idle
    /// The element under the cursor when a move began. It is the one that lands
    /// on the grid; everything else keeps its offset from it.
    private var moveAnchor: UUID?

    /// True from mouseDown until mouseUp. Views that care about the document's
    /// *shape* rather than its coordinates — the layer list — can skip work
    /// while this is set: a drag moves elements, it does not rename or reorder
    /// them, and `onChange` fires from the document's didSet on every frame.
    private(set) var isGestureActive = false
    private var downPanelPoint = CGPoint.zero
    private var didDrag = false

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isGestureActive = true
        // Reset here rather than per-branch. The marquee branch below used to
        // omit it, so a click on empty canvas after a resize or a group drag
        // inherited didDrag == true and the deselect on mouseUp never fired.
        didDrag = false
        let p = panelPoint(from: event)

        if event.clickCount == 2, let el = element(at: p), selection == [el.id] {
            // Double-click cycles nothing for now; keep selection.
        }

        // -1. Multi-selection: group resize / rotate handles.
        if selection.count > 1, let b = selectionBounds {
            let corner = activeHandles(for: b).contains { d, r in
                (d == .nw || d == .ne || d == .sw || d == .se) && r.contains(p)
            }
            let rp = CGPoint(x: b.midX, y: b.minY - overlayHandleOffset)
            if corner {
                downPanelPoint = p; didDrag = false
                dragMode = .groupResizing(orig: b, origFrames: frameMap())
                beginGestureUndo("Group Resize")
                return
            }
            if badgeRect(at: rp).contains(p) {
                downPanelPoint = p; didDrag = false
                dragMode = .groupRotating(center: CGPoint(x: b.midX, y: b.midY),
                                          startAngle: atan2(p.y - b.midY, p.x - b.midX),
                                          origFrames: frameMap(), origRotations: rotationMap())
                beginGestureUndo("Group Rotate")
                return
            }
        }

        // 0. Rotation / mirror handles (single selection).
        if let h = overlayHandle(at: p), let prim = primaryElement {
            switch h {
            case .rotate:
                dragMode = .rotating(origRotation: prim.rotation, center: prim.center,
                                     startAngle: atan2(p.y - prim.center.y, p.x - prim.center.x))
                beginGestureUndo("Rotate")
            case .mirrorX:
                dragMode = .mirroring(axis: .x, orig: prim.params.flipX)
            case .mirrorY:
                dragMode = .mirroring(axis: .y, orig: prim.params.flipY)
            }
            downPanelPoint = p
            didDrag = false
            return
        }

        // 1. Handles first (single selection; rotated elements resize along
        //    their own tilted axes -- see `toLocal`).
        if let dir = handle(at: p), let prim = primaryElement {
            downPanelPoint = p   // must anchor THIS click — stale anchor made resizes explode
            dragMode = .resizing(dir: dir, orig: prim.frame, rotation: prim.rotation, center: prim.center)
            beginGestureUndo("Resize")
            didDrag = false
            return
        }

        // 2. Hit test elements (topmost first). Groups are selected and moved
        //    as a unit: a click on any member expands to the whole group HERE,
        //    so the drag that follows carries every member with it. (Expanding
        //    only at mouseUp let a click-drag move a lone member out of its
        //    group, silently splitting it.)
        if let el = element(at: p) {
            moveAnchor = el.id
            let members = groupMembers(el.id)
            if !event.modifierFlags.isDisjoint(with: [.shift, .command]) {
                var sel = selection
                if sel.contains(el.id) { sel.subtract(members) } else { sel.formUnion(members) }
                setSelection(sel)
                if sel.contains(el.id) {
                    dragMode = .moving(origFrames: origFrames(for: sel))
                    beginGestureUndo("Move")
                } else {
                    dragMode = .idle
                }
            } else {
                if !selection.contains(el.id) {
                    setSelection(members)
                }
                dragMode = .moving(origFrames: origFrames(for: selection))
                beginGestureUndo("Move")
            }
            downPanelPoint = p
            didDrag = false
            return
        }

        // 3. Empty area → marquee (⇧ extends the current selection).
        let base = !event.modifierFlags.isDisjoint(with: [.shift, .command]) ? selection : []
        dragMode = .marquee(start: p, baseSelection: base)
        marqueeRect = CGRect(origin: p, size: .zero)
        downPanelPoint = p
    }

    private func origFrames(for ids: Set<UUID>) -> [UUID: CGRect] {
        var d: [UUID: CGRect] = [:]
        for el in document.elements where ids.contains(el.id) { d[el.id] = el.frame }
        return d
    }

    private func beginGestureUndo(_ name: String) {
        let old = document.elements
        edits.registerUndo(withTarget: self) { target in
            target.apply(elements: old, name: name)
        }
        suppressUndoRegistration = true
        lastUndoName = nil
    }

    private func endGesture() {
        suppressUndoRegistration = false
        lastUndoName = nil
    }

    override func mouseDragged(with event: NSEvent) {
        let p = panelPoint(from: event)
        let dx = p.x - downPanelPoint.x
        let dy = p.y - downPanelPoint.y
        if abs(dx) > 0.5 / zoom || abs(dy) > 0.5 / zoom { didDrag = true }

        switch dragMode {

        case .moving(let orig):
            // Snap the gesture once, from the element under the cursor, then
            // move everything by that same delta. Snapping each origin
            // independently pulls elements onto different grid points, so a
            // multi-selection drag silently destroyed any alignment between
            // them — which is exactly what "snap is messing up my alignment"
            // looks like from the outside.
            var sdx = dx, sdy = dy
            if let anchor = moveAnchor.flatMap({ orig[$0] }) ?? orig.values.first {
                switch snapMode {
                case .uniform:
                    sdx = snapVal(anchor.minX + dx) - anchor.minX
                    sdy = snapVal(anchor.minY + dy) - anchor.minY
                case .sergeGrid:
                    let center = CGPoint(x: anchor.midX + dx, y: anchor.midY + dy)
                    let snapped = snapEnabled ? SergeGrid.snapCenter(center, in: document) : center
                    sdx = snapped.x - anchor.midX
                    sdy = snapped.y - anchor.midY
                case .customGrid:
                    let center = CGPoint(x: anchor.midX + dx, y: anchor.midY + dy)
                    let snapped = snapEnabled ? CustomGrid.snapCenter(center, in: document) : center
                    sdx = snapped.x - anchor.midX
                    sdy = snapped.y - anchor.midY
                }
            }
            mutateFrames(orig) { frame in
                var nf = frame
                nf.origin.x = frame.minX + sdx
                nf.origin.y = frame.minY + sdy
                return nf
            }

        case .resizing(let dir, let orig, let rotation, let center):
            let localP = toLocal(p, rotation: rotation, center: center)
            let localDown = toLocal(downPanelPoint, rotation: rotation, center: center)
            let ldx = localP.x - localDown.x
            let ldy = localP.y - localDown.y
            var minX = orig.minX, minY = orig.minY
            var maxX = orig.maxX, maxY = orig.maxY
            let rawMinX = orig.minX + (dir == .nw || dir == .w || dir == .sw ? ldx : 0)
            let rawMaxX = orig.maxX + (dir == .ne || dir == .e || dir == .se ? ldx : 0)
            let rawMinY = orig.minY + (dir == .nw || dir == .n || dir == .ne ? ldy : 0)
            let rawMaxY = orig.maxY + (dir == .sw || dir == .s || dir == .se ? ldy : 0)
            if dir == .nw || dir == .w || dir == .sw { minX = min(snapVal(rawMinX), maxX - minSize) }
            if dir == .ne || dir == .e || dir == .se { maxX = max(snapVal(rawMaxX), minX + minSize) }
            if dir == .nw || dir == .n || dir == .ne { minY = min(snapVal(rawMinY), maxY - minSize) }
            if dir == .sw || dir == .s || dir == .se { maxY = max(snapVal(rawMaxY), minY + minSize) }
            let nf = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            updatePrimaryFrame(nf)

        case .marquee(let start, let base):
            let rect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                              width: abs(p.x - start.x), height: abs(p.y - start.y))
            marqueeRect = rect
            // Rubber-band hits expand to whole groups, so a marquee over part
            // of a group selects (and later moves) the group as one unit.
            let hitIDs = document.elements
                .filter { $0.isHidden != true && $0.isTemplate != true && $0.frame.intersects(rect) }
                .map(\.id)
            var hit = Set<UUID>()
            for id in hitIDs { hit.formUnion(groupMembers(id)) }
            selection = base.union(hit)
            needsDisplay = true

        case .groupResizing(let orig, let origFrames):
            let sx = orig.width > 0 ? max(0.05, (p.x - orig.minX) / orig.width) : 1
            let sy = orig.height > 0 ? max(0.05, (p.y - orig.minY) / orig.height) : 1
            var els = document.elements
            for i in els.indices where origFrames[els[i].id] != nil {
                let f = origFrames[els[i].id]!
                els[i].x = orig.minX + (f.minX - orig.minX) * sx
                els[i].y = orig.minY + (f.minY - orig.minY) * sy
                els[i].w = max(minSize, f.width * sx)
                els[i].h = max(minSize, f.height * sy)
            }
            document.elements = els
            needsDisplay = true
            notifyChange()

        case .groupRotating(let center, let startAngle, let origFrames, let origRotations):
            guard hypot(dx, dy) * zoom > rotateDeadZone else { break }
            var delta = (atan2(p.y - center.y, p.x - center.x) - startAngle) * 180 / .pi
            if event.modifierFlags.contains(.shift) { delta = (delta / 15).rounded() * 15 }
            if abs(delta) < rotateSnapToZero { delta = 0 }
            var els = document.elements
            for i in els.indices where origFrames[els[i].id] != nil {
                let f = origFrames[els[i].id]!
                let rc = Geo.rotate(CGPoint(x: f.midX, y: f.midY), around: center, degrees: delta)
                els[i].x = rc.x - f.width / 2
                els[i].y = rc.y - f.height / 2
                els[i].rotation = max(-180, min(180, (origRotations[els[i].id] ?? 0) + delta))
            }
            document.elements = els
            needsDisplay = true
            notifyChange()

        case .rotating(let origRotation, let center, let startAngle):
            // Dead zone. A click on the badge that drifts a pixel or two must
            // not impart a rotation too small to see but large enough to land
            // in the export as <g transform="rotate(-0.07 …)">.
            guard hypot(dx, dy) * zoom > rotateDeadZone else { break }
            let a = atan2(p.y - center.y, p.x - center.x)
            var deg = origRotation + (a - startAngle) * 180 / .pi
            if event.modifierFlags.contains(.shift) { deg = (deg / 15).rounded() * 15 }
            if abs(deg) < rotateSnapToZero { deg = 0 }   // let it pass cleanly through upright
            updatePrimaryRotation(max(-180, min(180, deg)))

        case .mirroring(let axis, let orig):
            let c = primaryElement?.center ?? downPanelPoint
            let crossed = axis == .x
                ? (p.x < c.x) != (downPanelPoint.x < c.x)
                : (p.y < c.y) != (downPanelPoint.y < c.y)
            updatePrimaryFlip(axis, orig != crossed)

        case .idle:
            break
        }
    }

    private let minSize: CGFloat = 6
    /// Screen pixels of travel before a rotate gesture engages at all.
    private let rotateDeadZone: CGFloat = 3
    /// Degrees within which rotation collapses to exactly upright.
    private let rotateSnapToZero: CGFloat = 0.25

    private func snapVal(_ v: CGFloat) -> CGFloat {
        snapEnabled ? Geo.snap(v, to: snapStep) : v.rounded(.toNearestOrAwayFromZero)
    }

    /// Snaps a *centre* point per the active snap mode. Used everywhere a
    /// placement is naturally described by its centre (stamp drops, palette
    /// drag-and-drop, "insert at panel centre").
    private func snappedCenter(_ p: CGPoint) -> CGPoint {
        switch snapMode {
        case .uniform:
            return CGPoint(x: snapVal(Geo.snap(p.x, to: Geo.defaultSnap)),
                           y: snapVal(Geo.snap(p.y, to: Geo.defaultSnap)))
        case .sergeGrid:
            return snapEnabled ? SergeGrid.snapCenter(p, in: document) : p
        case .customGrid:
            return snapEnabled ? CustomGrid.snapCenter(p, in: document) : p
        }
    }

    /// Snaps a *centre* point, then converts to the top-left origin an
    /// element of `size` needs to be centred there.
    private func snappedOrigin(forCenter point: CGPoint, size: CGSize) -> CGPoint {
        let c = snappedCenter(point)
        return CGPoint(x: c.x - size.width / 2, y: c.y - size.height / 2)
    }

    private func mutateFrames(_ orig: [UUID: CGRect], _ mapper: (CGRect) -> CGRect) {
        var els = document.elements
        for i in els.indices {
            if let o = orig[els[i].id] {
                els[i].frame = mapper(o)
            }
        }
        document.elements = els   // gesture path: no extra undo registration
        needsDisplay = true
        notifyChange()
    }

    private func updatePrimaryFrame(_ nf: CGRect) {
        var els = document.elements
        if let i = els.firstIndex(where: { $0.id == primaryElement?.id }) {
            els[i].frame = nf
        }
        document.elements = els   // gesture path: no extra undo registration
        needsDisplay = true
        notifyChange()
    }

    private var selectionBounds: CGRect? {
        let sel = document.elements.filter { selection.contains($0.id) }
        guard let first = sel.first else { return nil }
        var b = first.frame
        for el in sel.dropFirst() { b = b.union(el.frame) }
        return b
    }
    private func frameMap() -> [UUID: CGRect] {
        var d: [UUID: CGRect] = [:]
        for el in document.elements where selection.contains(el.id) { d[el.id] = el.frame }
        return d
    }
    private func rotationMap() -> [UUID: CGFloat] {
        var d: [UUID: CGFloat] = [:]
        for el in document.elements where selection.contains(el.id) { d[el.id] = el.rotation }
        return d
    }

    /// Align every selected element to the group bounding box (L/CX/R/T/CY/B).
    /// Align the selection. `to: "sel"` lines elements up with the selection's
    /// own bounding box (needs 2+ selected). `to: "panel"` aligns to the panel
    /// edges / center line and works with any selection size, even one element.
    /// Undoable wrapper around `PanelDocument.nameSequentially`.
    func nameSelectionSequentially(prefix: String) {
        var doc = document
        doc.nameSequentially(ids: selection, prefix: prefix)
        guard doc.elements != document.elements else { return }
        apply(elements: doc.elements, name: "Name Components")
    }

    /// Undoable wrapper around `PanelDocument.labelSelection`.
    ///
    /// The new labels end up selected. That is the point of the command: the
    /// inspector's Size row then writes to all of them at once, so twenty-five
    /// labels are still one action if the size is wrong.
    @discardableResult
    func labelSelection(placement: LabelPlacement,
                        gap: CGFloat,
                        fontSize: CGFloat,
                        bold: Bool,
                        uppercase: Bool,
                        spaceUnderscores: Bool,
                        colour: ColorSpec) -> (created: Int, skipped: Int) {
        let owners = selection
        var doc = document
        let result = doc.labelSelection(ids: owners, placement: placement, gap: gap,
                                        fontSize: fontSize, bold: bold, uppercase: uppercase,
                                        spaceUnderscores: spaceUnderscores, colour: colour)
        guard result.created > 0 else { return result }
        let made = Set(doc.elements.filter { el in
            el.kind == .text && (el.labelOwner.map(owners.contains) ?? false)
        }.map(\.id))
        apply(elements: doc.elements, name: "Label Selection")
        setSelection(made)
        return result
    }

    /// Undoable wrapper around `PanelDocument.setTemplate`.
    @discardableResult
    func setTemplate(_ on: Bool, ids: Set<UUID>? = nil) -> Int {
        var doc = document
        let scope = ids ?? (selection.isEmpty ? Set(document.elements.map(\.id)) : selection)
        let changed = doc.setTemplate(on, ids: scope)
        guard changed > 0 else { return 0 }
        apply(elements: doc.elements, name: on ? "Make Template" : "Make Editable")
        return changed
    }

    /// Undoable wrapper around `PanelDocument.fitToPanel`.
    @discardableResult
    func fitToPanel(_ mode: PanelDocument.FitMode, margin: CGFloat) -> Int {
        var doc = document
        let moved = doc.fitToPanel(mode, margin: margin)
        guard moved > 0 else { return 0 }
        apply(elements: doc.elements, name: "Fit to Panel")
        return moved
    }

    /// Undoable wrapper around `PanelDocument.nameFromLabels`.
    @discardableResult
    func nameFromLabels(within limit: CGFloat) -> (named: Int, skipped: Int) {
        var doc = document
        let scope = selection.isEmpty ? Set(document.elements.map(\.id)) : selection
        let result = doc.nameFromLabels(ids: scope, within: limit)
        guard result.named > 0 else { return result }
        apply(elements: doc.elements, name: "Name from Labels")
        return result
    }

    /// Undoable wrapper around `PanelDocument.adoptIdentifiers`.
    @discardableResult
    func adoptIdentifiers(from source: PanelDocument, within limit: CGFloat)
    -> (adopted: [PanelDocument.Adoption], unmatched: [String]) {
        var doc = document
        let scope = selection.isEmpty ? Set(document.elements.map(\.id)) : selection
        let result = doc.adoptIdentifiers(from: source, ids: scope, within: limit)
        guard !result.adopted.isEmpty else { return result }
        apply(elements: doc.elements, name: "Adopt Identifiers")
        return result
    }

    /// Undoable wrapper around `PanelDocument.makeWidget`.
    @discardableResult
    func makeWidget(name: String, role: ComponentRole) -> Bool {
        var doc = document
        guard doc.makeWidget(ids: selection, name: name, role: role) else { return false }
        apply(elements: doc.elements, name: "Make Widget")
        return true
    }

    /// Undoable wrapper around `PanelDocument.setColour`.
    func setColour(_ colour: ColorSpec, ids: [UUID], strokes: Bool, name: String) {
        var doc = document
        doc.setColour(colour, ids: ids, strokes: strokes)
        guard doc.elements != document.elements else { return }
        apply(elements: doc.elements, name: name)
    }

    /// Undoable wrapper around `PanelDocument.align`.
    func alignSelection(_ mode: String, to target: String = "sel") {
        let toPanel = target == "panel"
        var doc = document
        doc.align(mode, ids: selection, toPanel: toPanel)
        guard doc.elements != document.elements else { return }   // no empty undo steps
        apply(elements: doc.elements, name: toPanel ? "Align to Panel" : "Align")
    }

    /// Evenly distribute 3+ selected elements along an axis (first/last stay
    /// put either way). Two different notions of "evenly", picked via `by`:
    ///
    /// - `"gap"` (default): equal edge-to-edge spacing. Right when the
    ///   selection's own widths/heights should read as evenly separated --
    ///   e.g. a row of labels or icons where whitespace is what the eye
    ///   tracks.
    /// - `"center"`: equal centre-to-centre spacing, ignoring each
    ///   element's own size. Right when the selection's *positions* should
    ///   divide the span evenly regardless of what's sitting at each one --
    ///   e.g. two switches of one size splitting the run between two knobs
    ///   of a different size into thirds, which is a position statement
    ///   ("these four sit at 0, 1/3, 2/3, 1 of the span"), not a
    ///   whitespace statement. `"gap"` cannot express that when the
    ///   elements involved aren't all the same size, since equal edge gaps
    ///   and equal centre spacing only coincide when they are.
    func distributeSelection(_ axis: String, by mode: String = "gap") {
        let idxs = document.elements.indices.filter { selection.contains(document.elements[$0].id) }
        guard idxs.count > 2 else { return }
        var els = document.elements
        let sorted = idxs.sorted {
            axis == "X" ? els[$0].frame.minX < els[$1].frame.minX
                        : els[$0].frame.minY < els[$1].frame.minY
        }
        if mode == "center" {
            let firstCenter = axis == "X" ? els[sorted.first!].center.x : els[sorted.first!].center.y
            let lastCenter  = axis == "X" ? els[sorted.last!].center.x  : els[sorted.last!].center.y
            let step = (lastCenter - firstCenter) / CGFloat(sorted.count - 1)
            for (n, i) in sorted.enumerated() {
                let c = firstCenter + step * CGFloat(n)
                if axis == "X" { els[i].x = c - els[i].w / 2 }
                else { els[i].y = c - els[i].h / 2 }
            }
            apply(elements: els, name: "Distribute")
            return
        }
        let first = els[sorted.first!], last = els[sorted.last!]
        let span = axis == "X" ? last.frame.maxX - first.frame.minX
                               : last.frame.maxY - first.frame.minY
        let total = sorted.reduce(CGFloat(0)) {
            axis == "X" ? $0 + els[$1].w : $0 + els[$1].h
        }
        let gap = (span - total) / CGFloat(sorted.count - 1)
        var cursor = axis == "X" ? first.frame.minX : first.frame.minY
        for i in sorted {
            if axis == "X" { els[i].x = cursor; cursor += els[i].w + gap }
            else { els[i].y = cursor; cursor += els[i].h + gap }
        }
        apply(elements: els, name: "Distribute")
    }

    // MARK: Groups

    /// Assign a shared group ID to the selection; clicking any member then selects all.
    func groupSelection() {
        guard selection.count > 1 else { return }
        let gid = UUID()
        var els = document.elements
        for i in els.indices where selection.contains(els[i].id) { els[i].groupID = gid }
        apply(elements: els, name: "Group")
    }

    func ungroupSelection() {
        var els = document.elements
        var hit = false
        for i in els.indices where selection.contains(els[i].id) {
            if els[i].groupID != nil { els[i].groupID = nil; hit = true }
        }
        guard hit else { return }
        apply(elements: els, name: "Ungroup")
    }

    /// (internal: the layer list expands row clicks to whole groups too)
    func groupMembers(_ id: UUID) -> Set<UUID> {
        guard let el = document.elements.first(where: { $0.id == id }),
              let gid = el.groupID else { return [id] }
        return Set(document.elements.filter { $0.groupID == gid }.map(\.id))
    }

    /// Fresh group IDs for copied elements so duplicates and pastes never share
    /// membership with the elements they were copied from. Members of the same
    /// source group stay grouped together under one new ID.
    private func withRemappedGroups(_ els: [PanelElement]) -> [PanelElement] {
        var map: [UUID: UUID] = [:]
        return els.map { el in
            var e = el
            if let g = el.groupID {
                if map[g] == nil { map[g] = UUID() }
                e.groupID = map[g]
            }
            return e
        }
    }

    private func updatePrimaryRotation(_ deg: CGFloat) {
        var els = document.elements
        if let i = els.firstIndex(where: { $0.id == primaryElement?.id }) {
            els[i].rotation = deg
        }
        document.elements = els   // gesture path: no extra undo registration
        needsDisplay = true
        notifyChange()
    }

    private func updatePrimaryFlip(_ axis: MirrorAxis, _ on: Bool) {
        var els = document.elements
        if let i = els.firstIndex(where: { $0.id == primaryElement?.id }) {
            if axis == .x { els[i].params.flipX = on } else { els[i].params.flipY = on }
        }
        document.elements = els   // gesture path: no extra undo registration
        needsDisplay = true
        notifyChange()
    }

    override func mouseUp(with event: NSEvent) {
        isGestureActive = false   // before the switch: the notifications below flush the layer list
        switch dragMode {
        case .marquee:
            // A click on empty canvas with no drag clears the selection.
            // Previously nothing happened unless the mouse moved far enough to
            // start a rubber band, so deselecting meant finding a blank patch
            // and twitching.
            if !didDrag { setSelection([]) }
            marqueeRect = nil
            needsDisplay = true
            onSelectionChange?()
        case .moving, .resizing:
            endGesture()
            if !didDrag, case .moving = dragMode, event.modifierFlags.isDisjoint(with: [.shift, .command]),
               let p = element(at: panelPoint(from: event)) {
                setSelection(groupMembers(p.id))
            }
            onSelectionChange?()
        case .groupResizing, .groupRotating:
            endGesture()
            onSelectionChange?()
        case .rotating:
            endGesture()
            onSelectionChange?()
        case .mirroring(let axis, let orig):
            endGesture()
            if !didDrag { updatePrimaryFlip(axis, !orig) }   // plain click toggles
            onSelectionChange?()
        case .idle:
            break
        }
        dragMode = .idle
    }

    private func element(at p: CGPoint) -> PanelElement? {
        document.elements.reversed().first {
            $0.isHidden != true && $0.isTemplate != true && $0.contains(globalPoint: p)
        }
    }

    // MARK: Drag & drop from palette

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // "kind", "kind#preset" — a specific glyph, a ring knob, and so on —
        // or "stamp:<name>" for a saved fragment.
        guard let raw = sender.draggingPasteboard.string(forType: Paste.elementType) else { return false }
        let p0 = panelPoint(fromWindowLocation: sender.draggingLocation)
        if raw.hasPrefix(Paste.stampPrefix) {
            return insertStamp(named: String(raw.dropFirst(Paste.stampPrefix.count)), at: p0)
        }
        let parts = raw.split(separator: "#", maxSplits: 1).map(String.init)
        guard let kind = ElementKind(rawValue: parts[0]) else { return false }

        var el = kind.defaultElement(at: .zero)
        if parts.count > 1 { el.applyPreset(parts[1]) }
        let p = p0
        el.frame.origin = snappedOrigin(forCenter: p, size: CGSize(width: el.w, height: el.h))
        // Clamp inside the panel.
        el.frame.origin.x = max(0, min(el.frame.origin.x, document.pixelSize.width - el.w))
        el.frame.origin.y = max(0, min(el.frame.origin.y, document.pixelSize.height - el.h))
        insert([el], name: "Add \(kind.displayName)")
        return true
    }
}
