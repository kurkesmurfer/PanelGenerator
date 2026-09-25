import AppKit
import PanelKit
import PanelCanvas

/// Sidebar repository of primitives, shapes and symbols. Items drag onto the
/// canvas; double-click inserts at the panel centre.
///
/// Sections collapse and remember it, because this list only grows — forty-one
/// symbols already, and every widget added makes it longer.
final class PaletteView: NSView {

    /// The preset id is nil for a plain entry. Otherwise it is whatever the
    /// element kind understands: a symbol id, or a knob variant.
    var onInsert: ((ElementKind, String?) -> Void)?
    /// A saved fragment, by name. The canvas resolves it from the library.
    var onInsertStamp: ((String) -> Void)?

    private let scroll = NSScrollView()
    private let content = NSView()
    private var heightConstraint: NSLayoutConstraint!
    private var cursorY: CGFloat = 12
    private var collapsed: Set<String>

    private static let defaultsKey = "PaletteCollapsedSections"

    override var isFlipped: Bool { true }

    init() {
        collapsed = Set(UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? [])
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = ColorSpec.hex("#2B2B33").nsColor
        addSubview(scroll)

        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = content

        heightConstraint = content.heightAnchor.constraint(equalToConstant: 400)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            content.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            heightConstraint,
        ])

        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    // MARK: Sections

    private func isOpen(_ key: String) -> Bool { !collapsed.contains(key) }

    private func header(_ key: String) {
        let button = NSButton(frame: CGRect(x: 8, y: cursorY, width: 184, height: 18))
        button.isBordered = false
        button.alignment = .left
        button.attributedTitle = NSAttributedString(
            string: (isOpen(key) ? "▾  " : "▸  ") + key.uppercased(),
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: ColorSpec.hex("#9A9AB0").nsColor,
            ])
        button.identifier = NSUserInterfaceItemIdentifier(key)
        button.target = self
        button.action = #selector(toggleSection(_:))
        content.addSubview(button)
        cursorY += 22
    }

    @objc private func toggleSection(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        if collapsed.contains(key) { collapsed.remove(key) } else { collapsed.insert(key) }
        UserDefaults.standard.set(Array(collapsed).sorted(), forKey: Self.defaultsKey)
        // Not inline: this tears down the button that is still handling the click.
        DispatchQueue.main.async { [weak self] in self?.rebuild() }
    }

    private func items(_ key: String, _ entries: [(ElementKind, String?, String)]) {
        header(key)
        guard isOpen(key) else { return }
        for (kind, preset, title) in entries {
            let item = PaletteItemView(entry: (title, kind, preset))
            item.frame = CGRect(x: 8, y: cursorY, width: 184, height: 66)
            item.onInsert = { [weak self] kind, preset in self?.onInsert?(kind, preset) }
            content.addSubview(item)
            cursorY += 70
        }
        cursorY += 6
    }

    private func symbolGrid(_ key: String) {
        header(key)
        guard isOpen(key) else { return }
        let size: CGFloat = 42
        let columns = 4
        for (i, spec) in SymbolCatalogue.all.enumerated() {
            let cell = SymbolPaletteCell(symbolID: spec.id)
            cell.frame = CGRect(x: 8 + CGFloat(i % columns) * (size + 4),
                                y: cursorY + CGFloat(i / columns) * (size + 4),
                                width: size, height: size)
            cell.onInsert = { [weak self] id in self?.onInsert?(.symbol, id) }
            content.addSubview(cell)
        }
        let rows = (SymbolCatalogue.all.count + columns - 1) / columns
        cursorY += CGFloat(rows) * (size + 4) + 6
    }

    /// Saved fragments — a brand mark, a wordmark, a row of jacks. Empty until
    /// something is saved, with a line saying how, because an empty section
    /// that never explains itself just looks broken.
    private func stamps(_ key: String, category: String?) {
        header(key)
        guard isOpen(key) else { return }

        let library = StampLibrary.list().filter { $0.category == category }
        guard !library.isEmpty else {
            let note = NSTextField(wrappingLabelWithString:
                "Nothing saved yet. Select part of a panel and use Edit ▸ Add Selection to Palette.")
            note.font = NSFont.systemFont(ofSize: 10)
            note.textColor = ColorSpec.hex("#7E7E92").nsColor
            note.maximumNumberOfLines = 3
            note.frame = CGRect(x: 10, y: cursorY, width: 180, height: 40)
            content.addSubview(note)
            cursorY += 46
            return
        }

        for stamp in library {
            let item = StampItemView(stamp: stamp.resolved)
            item.frame = CGRect(x: 8, y: cursorY, width: 184, height: 66)
            item.onInsert = { [weak self] name in self?.onInsertStamp?(name) }
            content.addSubview(item)
            cursorY += 70
        }
        cursorY += 6
    }

    func rebuild() {
        content.subviews.forEach { $0.removeFromSuperview() }
        cursorY = 12

        // Generic primitives and shapes first, then one section per design
        // language (Styles/ in PanelKit).
        for section in DesignLanguage.paletteSections {
            items(section.title, section.entries.map { ($0.kind, $0.preset, $0.title) })
        }

        symbolGrid("Symbols")

        items("Text", [(.text, nil, "Text Label")])
        stamps("Stamps", category: nil)

        // One section per populated stamp subfolder -- a category earns its
        // own header the moment it has anything in it, so a fresh single-
        // sided stamp dropped in a new folder shows up without a code change.
        for category in StampLibrary.categories() {
            stamps(category, category: category)
        }

        heightConstraint.constant = cursorY + 12
    }
}

// MARK: - Item view (drag source)

final class PaletteItemView: NSView {

    typealias Entry = (title: String, kind: ElementKind, preset: String?)

    var entry: Entry
    var onInsert: ((ElementKind, String?) -> Void)?

    private var sampleElement: PanelElement
    private let previewRect = CGRect(x: 0, y: 0, width: 46, height: 46)

    init(entry: Entry) {
        self.entry = entry
        self.sampleElement = Self.previewSample(for: entry.kind, preset: entry.preset)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    static func previewSample(for kind: ElementKind, preset: String?) -> PanelElement {
        var e = kind.defaultElement(at: .zero)
        if let preset { e.applyPreset(preset) }
        switch kind {
        case .faderVertical: e.w = 20; e.h = 44
        case .faderHorizontal: e.w = 44; e.h = 20
        case .text:
            e.params.text = "Aa"; e.params.fontSize = 16; e.w = 40; e.h = 24
        case .box:
            // Only force the plain thumbnail sizing when there's no notch --
            // a notched preset already picked a frame its own tab makes
            // sense in, and squashing it to 46x18 would clip or distort it.
            if e.params.notchEdge == 0 {
                e.w = 46; e.h = 18
                e.params.cornerTL = 9; e.params.cornerTR = 9; e.params.cornerBR = 9; e.params.cornerBL = 9
            }
        case .elbow:
            e.w = 44; e.h = 44; e.params.armH = 32; e.params.armV = 32
            e.params.thickness = 11; e.params.thicknessV = 11; e.params.innerRadius = 5
        case .swirl:
            e.w = 34; e.h = 60; e.params.armH = 27; e.params.armH2 = 27; e.params.armV = 22
            e.params.thickness = 9; e.params.thicknessV = 9; e.params.innerRadius = 4
        case .line:
            e.w = 26; e.h = 56
        default: break
        }
        return e
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        ColorSpec.hex("#34343E").nsColor.setFill()
        bounds.fill()

        let area = CGRect(x: 10, y: (bounds.height - previewRect.height) / 2 + 4,
                          width: previewRect.width, height: previewRect.height)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        let sw = max(sampleElement.w, 1), sh = max(sampleElement.h, 1)
        let s = min(area.width / sw, area.height / sh, 2.2)
        ctx.translateBy(x: area.midX - sw * s / 2, y: area.midY - sh * s / 2)
        ctx.scaleBy(x: s, y: s)
        for part in Renderer.parts(for: sampleElement) {
            if let f = part.fill {
                ctx.saveGState(); ctx.addPath(part.path); ctx.setFillColor(f.nsColor.cgColor); ctx.fillPath(); ctx.restoreGState()
            }
            if let st = part.stroke {
                ctx.saveGState(); ctx.addPath(part.path); ctx.setStrokeColor(st.nsColor.cgColor)
                ctx.setLineWidth(part.lineWidth / s * min(s, 1)); ctx.strokePath(); ctx.restoreGState()
            }
        }
        ctx.restoreGState()

        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.88),
            .paragraphStyle: para,
        ]
        NSString(string: entry.title).draw(
            in: CGRect(x: 64, y: bounds.midY - 8, width: bounds.width - 72, height: 30),
            withAttributes: attrs)
    }

    // MARK: Dragging

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onInsert?(entry.kind, entry.preset)
            return
        }

        // The dragging item's pasteboard writer decides which types reach the
        // drag pasteboard. An NSString writes only .string, and the canvas is
        // registered for Paste.elementType alone — so the drop was refused and
        // nothing happened.
        var payload = entry.kind.rawValue
        if let preset = entry.preset { payload += "#" + preset }
        let pbItem = NSPasteboardItem()
        pbItem.setString(payload, forType: CanvasView.Paste.elementType)
        pbItem.setString(payload, forType: .string)

        let snapshot = NSImage(size: bounds.size, flipped: true) { [weak self] rect in
            self?.draw(rect)
            return true
        }

        let item = NSDraggingItem(pasteboardWriter: pbItem)
        item.setDraggingFrame(bounds, contents: snapshot)
        beginDraggingSession(with: [item], event: event, source: self)
    }
}

extension PaletteItemView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}

// MARK: - Stamp cell (drag source)

/// A saved fragment in the palette. Draws every element it holds, scaled to the
/// swatch, so the preview is the artwork itself rather than an icon standing in
/// for it.
final class StampItemView: NSView {

    private let stamp: StampLibrary.Stamp
    var onInsert: ((String) -> Void)?

    private let previewRect = CGRect(x: 0, y: 0, width: 46, height: 46)

    init(stamp: StampLibrary.Stamp) {
        self.stamp = stamp
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
        toolTip = "\(stamp.name) — \(stamp.elements.count) element"
            + (stamp.elements.count == 1 ? "" : "s")
            + String(format: ", %.1f × %.1f mm",
                     PanelMetrics.mm(stamp.bounds.width), PanelMetrics.mm(stamp.bounds.height))
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        ColorSpec.hex("#34343E").nsColor.setFill()
        bounds.fill()

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let area = CGRect(x: 10, y: (bounds.height - previewRect.height) / 2 + 4,
                          width: previewRect.width, height: previewRect.height)
        let box = stamp.bounds
        let sw = max(box.width, 1), sh = max(box.height, 1)
        let s = min(area.width / sw, area.height / sh, 2.2)

        ctx.saveGState()
        ctx.translateBy(x: area.midX - sw * s / 2, y: area.midY - sh * s / 2)
        ctx.scaleBy(x: s, y: s)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        for element in stamp.elements where element.isHidden != true {
            for part in Renderer.parts(for: element) {
                if let f = part.fill {
                    ctx.saveGState(); ctx.addPath(part.path)
                    ctx.setFillColor(f.nsColor.cgColor); ctx.fillPath(); ctx.restoreGState()
                }
                if let st = part.stroke {
                    ctx.saveGState(); ctx.addPath(part.path)
                    ctx.setStrokeColor(st.nsColor.cgColor)
                    ctx.setLineWidth(part.lineWidth); ctx.strokePath(); ctx.restoreGState()
                }
            }
        }
        ctx.restoreGState()

        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byTruncatingTail
        NSString(string: stamp.name).draw(
            in: CGRect(x: 64, y: bounds.midY - 8, width: bounds.width - 72, height: 30),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.88),
                .paragraphStyle: para,
            ])
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onInsert?(stamp.name)
            return
        }
        let payload = CanvasView.Paste.stampPrefix + stamp.name
        let pbItem = NSPasteboardItem()
        pbItem.setString(payload, forType: CanvasView.Paste.elementType)
        pbItem.setString(payload, forType: .string)

        let snapshot = NSImage(size: bounds.size, flipped: true) { [weak self] rect in
            self?.draw(rect)
            return true
        }
        let item = NSDraggingItem(pasteboardWriter: pbItem)
        item.setDraggingFrame(bounds, contents: snapshot)
        beginDraggingSession(with: [item], event: event, source: self)
    }
}

extension StampItemView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
