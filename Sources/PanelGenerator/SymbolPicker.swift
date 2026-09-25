import AppKit
import PanelKit
import PanelCanvas

// MARK: - Swatches
//
// The swatch *is* the symbol: drawn through the same catalogue path the panel
// uses, at the size of the cell. There are no icon assets to draw or keep in
// step, and a symbol added to the catalogue appears in every picker for free —
// the same property that lets the inspector build its parameter rows from the
// spec.

enum SymbolSwatch {

    static func draw(_ id: String, in rect: CGRect, color: ColorSpec, ctx: CGContext) {
        guard rect.width > 1, rect.height > 1 else { return }
        var el = ElementKind.symbol.defaultElement(at: rect.origin)
        el.w = rect.width
        el.h = rect.height
        el.fill = color
        el.applySymbol(id)
        ctx.saveGState()
        ctx.addPath(SymbolCatalogue.path(for: el))
        ctx.setFillColor(color.nsColor.cgColor)
        ctx.fillPath()
        ctx.restoreGState()
    }

    static func image(_ id: String, size: CGSize, color: ColorSpec) -> NSImage {
        NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            draw(id, in: rect.insetBy(dx: 1.5, dy: 1.5), color: color, ctx: ctx)
            return true
        }
    }
}

// MARK: - Grid

/// Click-to-pick grid, sectioned by family. Used inside the inspector popover.
final class SymbolGridView: NSView {

    var onPick: ((String) -> Void)?

    private let cell: CGFloat = 40
    private let columns = 6
    private let pad: CGFloat = 10

    override var isFlipped: Bool { true }

    /// Swatches render in the element's own fill, so you are choosing a glyph
    /// against the colour it will actually be rather than against a grey.
    func build(color: ColorSpec, selected: String) {
        subviews.forEach { $0.removeFromSuperview() }
        var y = pad

        for category in SymbolCategory.allCases {
            let specs = SymbolCatalogue.specs(in: category)
            guard !specs.isEmpty else { continue }

            let header = NSTextField(labelWithString: category.displayName.uppercased())
            header.font = NSFont.systemFont(ofSize: 9, weight: .bold)
            header.textColor = .secondaryLabelColor
            header.frame = CGRect(x: pad, y: y, width: 220, height: 12)
            addSubview(header)
            y += 16

            for (i, spec) in specs.enumerated() {
                let column = i % columns
                let row = i / columns
                let button = NSButton(frame: CGRect(x: pad + CGFloat(column) * (cell + 4),
                                                    y: y + CGFloat(row) * (cell + 4),
                                                    width: cell, height: cell))
                button.title = ""
                button.image = SymbolSwatch.image(spec.id,
                                                  size: CGSize(width: cell - 8, height: cell - 8),
                                                  color: color)
                button.imagePosition = .imageOnly
                button.isBordered = false
                button.wantsLayer = true
                button.layer?.cornerRadius = 5
                button.layer?.backgroundColor = (spec.id == selected
                    ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.6)
                    : NSColor.white.withAlphaComponent(0.06)).cgColor
                button.toolTip = spec.name
                button.identifier = NSUserInterfaceItemIdentifier(spec.id)
                button.target = self
                button.action = #selector(pick(_:))
                addSubview(button)
            }
            y += CGFloat((specs.count + columns - 1) / columns) * (cell + 4) + 8
        }

        frame = CGRect(x: 0, y: 0,
                       width: pad * 2 + CGFloat(columns) * (cell + 4) - 4,
                       height: y)
    }

    @objc private func pick(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        onPick?(id)
    }
}

// MARK: - Popover

enum SymbolPicker {

    static func present(from anchor: NSView,
                        color: ColorSpec,
                        selected: String,
                        onPick: @escaping (String) -> Void) {
        let grid = SymbolGridView()
        grid.build(color: color, selected: selected)

        let controller = NSViewController()
        controller.view = grid

        let popover = NSPopover()
        popover.contentViewController = controller
        popover.contentSize = grid.frame.size
        popover.behavior = .transient
        grid.onPick = { [weak popover] id in
            onPick(id)
            popover?.performClose(nil)
        }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }
}

// MARK: - Palette cell

/// One draggable symbol in the left-hand repo. Drops carry the symbol id
/// alongside the kind, so you place the glyph you picked rather than placing a
/// sine and changing it afterwards.
final class SymbolPaletteCell: NSView {

    let symbolID: String
    var onInsert: ((String) -> Void)?

    init(symbolID: String) {
        self.symbolID = symbolID
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        toolTip = SymbolCatalogue.spec(symbolID).name
    }
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        ColorSpec.hex("#34343E").nsColor.setFill()
        bounds.fill()
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        SymbolSwatch.draw(symbolID, in: bounds.insetBy(dx: 6, dy: 6),
                          color: .hex("#D8DCE6"), ctx: ctx)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onInsert?(symbolID)
            return
        }
        let item = NSPasteboardItem()
        item.setString(ElementKind.symbol.rawValue + "#" + symbolID,
                       forType: CanvasView.Paste.elementType)
        item.setString(symbolID, forType: .string)

        let snapshot = NSImage(size: bounds.size, flipped: true) { [weak self] rect in
            self?.draw(rect)
            return true
        }
        let dragging = NSDraggingItem(pasteboardWriter: item)
        dragging.setDraggingFrame(bounds, contents: snapshot)
        beginDraggingSession(with: [dragging], event: event, source: self)
    }
}

extension SymbolPaletteCell: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
