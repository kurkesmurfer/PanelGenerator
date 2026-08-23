import AppKit

/// Sidebar repository of primitives & shapes. Items drag onto the canvas;
/// double-click inserts at the panel centre.
final class PaletteView: NSView {

    var onInsert: ((ElementKind) -> Void)?

    private struct Entry {
        let title: String
        let kind: ElementKind
    }

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = ColorSpec.hex("#2B2B33").nsColor
        addSubview(scroll)

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = content

        var y: CGFloat = 12
        func header(_ t: String) {
            let l = NSTextField(labelWithString: t.uppercased())
            l.font = NSFont.systemFont(ofSize: 10, weight: .bold)
            l.textColor = ColorSpec.hex("#9A9AB0").nsColor
            l.frame = CGRect(x: 14, y: y, width: 180, height: 16)
            content.addSubview(l)
            y += 22
        }
        func section(_ kinds: [ElementKind]) {
            for k in kinds {
                let item = PaletteItemView(entry: (k.displayName, k))
                item.frame = CGRect(x: 8, y: y, width: 184, height: 66)
                item.onInsert = { [weak self] kind in self?.onInsert?(kind) }
                content.addSubview(item)
                y += 70
            }
            y += 6
        }

        header("Primitives")
        section([.jack, .knobLarge, .knobMedium, .knobSmall,
                 .faderVertical, .faderHorizontal, .led, .screw, .pushButton, .buttonGroup])
        header("Shapes · Backdrop")
        section([.box, .ellipse, .triangle, .elbow, .ringSector])
        header("Text")
        section([.text])

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            content.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            content.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            content.heightAnchor.constraint(equalToConstant: y + 12),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not supported") }
}

// MARK: - Item view (drag source)

final class PaletteItemView: NSView {

    typealias Entry = (title: String, kind: ElementKind)

    var entry: Entry
    var onInsert: ((ElementKind) -> Void)?

    private var sampleElement: PanelElement
    private let previewRect = CGRect(x: 0, y: 0, width: 46, height: 46)

    init(entry: Entry) {
        self.entry = entry
        self.sampleElement = Self.previewSample(for: entry.kind)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 6
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    static func previewSample(for kind: ElementKind) -> PanelElement {
        var e = kind.defaultElement(at: .zero)
        switch kind {
        case .faderVertical: e.w = 20; e.h = 44
        case .faderHorizontal: e.w = 44; e.h = 20
        case .text:
            e.params.text = "Aa"; e.params.fontSize = 16; e.w = 40; e.h = 24
        case .box:
            e.w = 46; e.h = 18
            e.params.cornerTL = 9; e.params.cornerTR = 9; e.params.cornerBR = 9; e.params.cornerBL = 9
        case .elbow:
            e.w = 44; e.h = 44; e.params.armH = 16; e.params.armV = 16
            e.params.thickness = 11; e.params.innerRadius = 5
        default: break
        }
        return e
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        // Card background
        ColorSpec.hex("#34343E").nsColor.setFill()
        bounds.fill()

        // Preview area
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
        if sampleElement.kind == .text {
            Renderer.drawText(sampleElement, in: ctx)
        }
        ctx.restoreGState()

        // Caption
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
            onInsert?(entry.kind)
            return
        }

        let pbName = NSPasteboard.Name("pg-drag-" + UUID().uuidString)
        let pb = NSPasteboard(name: pbName)
        pb.declareTypes([CanvasView.Paste.elementType], owner: nil)
        pb.setString(entry.kind.rawValue, forType: CanvasView.Paste.elementType)

        // Pre-render the drag snapshot (simpler and more reliable than a
        // contents provider for this prototype).
        let snapshot = NSImage(size: bounds.size, flipped: true) { [weak self] rect in
            self?.draw(rect)
            return true
        }

        let item = NSDraggingItem(pasteboardWriter: entry.kind.rawValue as NSString)
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
