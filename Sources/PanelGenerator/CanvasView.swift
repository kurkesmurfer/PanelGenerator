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

    func resizeToFitDocument() {
        let s = document.pixelSize
        let newSize = CGSize(width: s.width * zoom + Self.margin * 2,
                             height: s.height * zoom + Self.margin * 2)
        if frame.size != newSize {
            frame.size = newSize
        }
    }

    /// Convert a window event location into panel pixel coordinates.
    func panelPoint(from event: NSEvent) -> CGPoint {
        let loc = convert(event.locationInWindow, from: nil)
        return CGPoint(x: (loc.x - Self.margin) / zoom,
                       y: (loc.y - Self.margin) / zoom)
    }
    func panelPoint(fromWindowLocation loc: NSPoint) -> CGPoint {
        let p = convert(loc, from: nil)
        return CGPoint(x: (p.x - Self.margin) / zoom,
                       y: (p.y - Self.margin) / zoom)
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
        insert(pasted, name: "Paste")
        setSelection(Set(pasted.map(\.id)))
    }

    func insertAtCenter(_ kind: ElementKind) {
        var el = kind.defaultElement(at: .zero)
        el.frame.origin = CGPoint(
            x: Geo.snap(document.pixelSize.width / 2 - el.w / 2, to: Geo.defaultSnap),
            y: Geo.snap(document.pixelSize.height / 2 - el.h / 2, to: Geo.defaultSnap))
        el.frame.origin.x = max(0, min(el.frame.origin.x, document.pixelSize.width - el.w))
        el.frame.origin.y = max(0, min(el.frame.origin.y, document.pixelSize.height - el.h))
        insert([el], name: "Add \(kind.displayName)")
    }

    // MARK: Selection & edit commands

    func setSelection(_ ids: Set<UUID>) {
        selection = ids
        needsDisplay = true
        onSelectionChange?()
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
        insert(copies, name: "Duplicate")
    }

    func selectAllElements() {
        setSelection(Set(document.elements.map(\.id)))
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

        // ⌫ (backspace) and ⌦ (forward delete) both delete the selection.
        if chars == "\u{7F}" || chars == "\u{F728}" || event.keyCode == 51 || event.keyCode == 117 {
            deleteSelection()
            return
        }

        // Arrow keys nudge the selection (⇧ nudges by the snap-grid step).
        let step: CGFloat = event.modifierFlags.contains(.shift) ? Geo.defaultSnap : 1
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
        ctx.translateBy(x: Self.margin, y: Self.margin)
        ctx.scaleBy(x: zoom, y: zoom)

        // Panel shadow
        let panelRect = CGRect(origin: .zero, size: document.pixelSize)
        ctx.setShadow(offset: CGSize(width: 0, height: -3 / zoom), blur: 10 / zoom,
                      color: NSColor.black.withAlphaComponent(0.55).cgColor)
        ctx.setFillColor(document.background.nsColor.cgColor)
        ctx.fill(panelRect.insetBy(dx: -1, dy: -1).offsetBy(dx: 0, dy: 0))
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        Renderer.drawBackground(document, in: ctx)
        drawGrid(in: ctx)

        for el in document.elements {
            Renderer.draw(el, in: ctx)
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

    private func transformedPath(for el: PanelElement) -> CGPath {
        guard el.rotation != 0 else { return CGPath(rect: el.frame, transform: nil) }
        var t = CGAffineTransform(translationX: el.center.x, y: el.center.y)
        t = t.rotated(by: Geo.deg2rad(el.rotation))
        t = t.translatedBy(x: -el.center.x, y: -el.center.y)
        return CGPath(rect: el.frame, transform: &t)
    }

    private func drawSelectionOverlay(in ctx: CGContext) {
        let ids = selection
        guard !ids.isEmpty else { return }

        for el in document.elements where ids.contains(el.id) {
            ctx.saveGState()
            ctx.addPath(transformedPath(for: el))
            ctx.setStrokeColor(ColorSpec.hex("#4FC3F7").nsColor.cgColor)
            ctx.setLineWidth(1.2 / zoom)
            ctx.setLineDash(phase: 0, lengths: [4 / zoom, 3 / zoom])
            ctx.strokePath()
            ctx.restoreGState()
        }

        // Resize handles only make sense unrotated, single-selection.
        if let p = primaryElement, p.rotation == 0 {
            let hs = handleSize
            for (_, r) in activeHandles(for: p.frame) {
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(r.insetBy(dx: -hs / 2, dy: -hs / 2))
                ctx.setStrokeColor(NSColor.black.cgColor)
                ctx.setLineWidth(1 / zoom)
                ctx.stroke(r.insetBy(dx: -hs / 2, dy: -hs / 2))
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
        guard let prim = primaryElement, prim.rotation == 0 else { return nil }
        for (dir, r) in activeHandles(for: prim.frame) where r.contains(p) {
            return dir
        }
        return nil
    }

    // MARK: Rotation & mirror overlay handles

    private var overlayHandleSize: CGFloat { 11 / zoom }
    private var overlayHandleOffset: CGFloat { 18 / zoom }

    private var rotateHandlePoint: CGPoint? {
        guard let f = primaryElement?.frame else { return nil }
        return CGPoint(x: f.midX, y: f.minY - overlayHandleOffset)
    }

    /// Mirror handles only for kinds whose renderer honours flipX / flipY (elbow).
    private var mirrorHandlePoints: (x: CGPoint, y: CGPoint)? {
        guard let el = primaryElement, el.kind == .elbow else { return nil }
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
        case resizing(dir: HandleDir, orig: CGRect)
        case rotating(origRotation: CGFloat, center: CGPoint, startAngle: CGFloat)
        case mirroring(axis: MirrorAxis, orig: Bool)
        case marquee(start: CGPoint, baseSelection: Set<UUID>)
    }

    /// Mirror axis controlled by an overlay handle.
    enum MirrorAxis { case x, y }
    private enum OverlayHandle { case rotate, mirrorX, mirrorY }

    private var dragMode: DragMode = .idle
    private var downPanelPoint = CGPoint.zero
    private var didDrag = false

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = panelPoint(from: event)

        if event.clickCount == 2, let el = element(at: p), selection == [el.id] {
            // Double-click cycles nothing for now; keep selection.
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

        // 1. Handles first (single, unrotated selection).
        if let dir = handle(at: p), let prim = primaryElement {
            dragMode = .resizing(dir: dir, orig: prim.frame)
            beginGestureUndo("Resize")
            didDrag = false
            return
        }

        // 2. Hit test elements (topmost first).
        if let el = element(at: p) {
            if event.modifierFlags.contains(.shift) {
                var sel = selection
                if sel.contains(el.id) { sel.remove(el.id) } else { sel.insert(el.id) }
                setSelection(sel)
                if sel.contains(el.id) {
                    dragMode = .moving(origFrames: origFrames(for: sel))
                    beginGestureUndo("Move")
                } else {
                    dragMode = .idle
                }
            } else {
                if !selection.contains(el.id) {
                    setSelection([el.id])
                }
                dragMode = .moving(origFrames: origFrames(for: selection))
                beginGestureUndo("Move")
            }
            downPanelPoint = p
            didDrag = false
            return
        }

        // 3. Empty area → marquee (or plain deselect).
        if event.modifierFlags.contains(.shift) {
            dragMode = .idle
        } else {
            dragMode = .marquee(start: p, baseSelection: [])
            marqueeRect = CGRect(origin: p, size: .zero)
        }
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
            mutateFrames(orig) { frame in
                var nf = frame
                nf.origin.x = snapVal(frame.minX + dx)
                nf.origin.y = snapVal(frame.minY + dy)
                return nf
            }

        case .resizing(let dir, let orig):
            var minX = orig.minX, minY = orig.minY
            var maxX = orig.maxX, maxY = orig.maxY
            let rawMinX = orig.minX + (dir == .nw || dir == .w || dir == .sw ? dx : 0)
            let rawMaxX = orig.maxX + (dir == .ne || dir == .e || dir == .se ? dx : 0)
            let rawMinY = orig.minY + (dir == .nw || dir == .n || dir == .ne ? dy : 0)
            let rawMaxY = orig.maxY + (dir == .sw || dir == .s || dir == .se ? dy : 0)
            if dir == .nw || dir == .w || dir == .sw { minX = min(snapVal(rawMinX), maxX - minSize) }
            if dir == .ne || dir == .e || dir == .se { maxX = max(snapVal(rawMaxX), minX + minSize) }
            if dir == .nw || dir == .n || dir == .ne { minY = min(snapVal(rawMinY), maxY - minSize) }
            if dir == .sw || dir == .s || dir == .se { maxY = max(snapVal(rawMaxY), minY + minSize) }
            let nf = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            updatePrimaryFrame(nf)

        case .marquee(let start, let base):
            let rect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                              width: abs(dx), height: abs(dy))
            marqueeRect = rect
            let hit = Set(document.elements.filter { $0.frame.intersects(rect) }.map(\.id))
            selection = base.union(hit)
            needsDisplay = true

        case .rotating(let origRotation, let center, let startAngle):
            let a = atan2(p.y - center.y, p.x - center.x)
            var deg = origRotation + (a - startAngle) * 180 / .pi
            if event.modifierFlags.contains(.shift) { deg = (deg / 15).rounded() * 15 }
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

    private func snapVal(_ v: CGFloat) -> CGFloat {
        snapEnabled ? Geo.snap(v, to: Geo.defaultSnap) : v.rounded(.toNearestOrAwayFromZero)
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
        switch dragMode {
        case .marquee:
            marqueeRect = nil
            needsDisplay = true
            onSelectionChange?()
        case .moving, .resizing:
            endGesture()
            if !didDrag, case .moving = dragMode, !event.modifierFlags.contains(.shift),
               let p = element(at: panelPoint(from: event)) {
                setSelection([p.id])
            }
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
        document.elements.reversed().first { $0.contains(globalPoint: p) }
    }

    // MARK: Drag & drop from palette

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let raw = sender.draggingPasteboard.string(forType: Paste.elementType),
              let kind = ElementKind(rawValue: raw) else { return false }

        var el = kind.defaultElement(at: .zero)
        let p = panelPoint(fromWindowLocation: sender.draggingLocation)
        el.frame.origin = CGPoint(
            x: snapVal(Geo.snap(p.x - el.w / 2, to: Geo.defaultSnap)),
            y: snapVal(Geo.snap(p.y - el.h / 2, to: Geo.defaultSnap)))
        // Clamp inside the panel.
        el.frame.origin.x = max(0, min(el.frame.origin.x, document.pixelSize.width - el.w))
        el.frame.origin.y = max(0, min(el.frame.origin.y, document.pixelSize.height - el.h))
        insert([el], name: "Add \(kind.displayName)")
        return true
    }
}
