import AppKit

/// Bottom of the left sidebar: z-ordered element list, top layer first.
/// Click selects · ⇧/⌘-click extends · ◉/○ toggles visibility · ▲▼ reorder.
final class LayerListView: NSView {

    weak var canvas: CanvasView?
    private let rowH: CGFloat = 22

    override var isFlipped: Bool { true }

    func rebuild() {
        for sub in subviews { sub.removeFromSuperview() }
        guard let cv = canvas else { return }
        let doc = cv.document

        let header = NSTextField(labelWithString: "LAYERS — \(doc.elements.count)")
        header.font = NSFont.boldSystemFont(ofSize: 9)
        header.textColor = .secondaryLabelColor
        header.frame = CGRect(x: 10, y: 5, width: max(bounds.width - 20, 160), height: 13)
        addSubview(header)

        for (i, el) in doc.elements.reversed().enumerated() {
            let row = LayerRowView(frame: CGRect(x: 0, y: 22 + CGFloat(i) * rowH,
                                                 width: bounds.width, height: rowH))
            row.configure(element: el, selected: cv.selection.contains(el.id), list: self)
            addSubview(row)
        }
    }

    func select(_ id: UUID, additive: Bool) {
        guard let cv = canvas else { return }
        let members = cv.groupMembers(id)   // groups select/toggle as one unit
        if additive {
            var s = cv.selection
            if s.contains(id) { s.subtract(members) } else { s.formUnion(members) }
            cv.setSelection(s)
        } else {
            cv.setSelection(members)
        }
    }

    func toggleHidden(_ id: UUID) {
        guard let cv = canvas else { return }
        var els = cv.document.elements
        guard let i = els.firstIndex(where: { $0.id == id }) else { return }
        els[i].isHidden = els[i].isHidden == true ? nil : true
        let hiding = els[i].isHidden == true
        cv.apply(elements: els, name: hiding ? "Hide Element" : "Show Element")
    }

    func move(_ id: UUID, delta: Int) {
        guard let cv = canvas else { return }
        var els = cv.document.elements
        guard let i = els.firstIndex(where: { $0.id == id }) else { return }
        let j = max(0, min(els.count - 1, i + delta))
        guard j != i else { return }
        els.insert(els.remove(at: i), at: j)
        cv.apply(elements: els, name: "Reorder Layers")
    }
}

/// One row: visibility toggle, name, up/down reorder buttons.
final class LayerRowView: NSView {

    private var elementID: UUID?
    private weak var list: LayerListView?
    private var hiddenState = false

    func configure(element: PanelElement, selected: Bool, list: LayerListView) {
        self.elementID = element.id
        self.list = list
        hiddenState = element.isHidden == true
        wantsLayer = true
        layer?.backgroundColor = selected
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.55).cgColor
            : NSColor.clear.cgColor

        let base = element.name.isEmpty ? element.kind.displayName : element.name
        let title = element.groupID != nil ? "▸ " + base : base
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = hiddenState ? .secondaryLabelColor : .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.frame = CGRect(x: 26, y: 4, width: max(bounds.width - 84, 60), height: 14)
        addSubview(label)

        makeButton(hiddenState ? "○" : "◉", x: 6, action: #selector(eyeTapped))
        makeButton("▲", x: bounds.width - 40, action: #selector(upTapped))
        makeButton("▼", x: bounds.width - 22, action: #selector(downTapped))
    }

    private func makeButton(_ title: String, x: CGFloat, action: Selector) {
        let b = NSButton(title: title, target: self, action: action)
        b.isBordered = false
        b.font = NSFont.systemFont(ofSize: 9)
        b.frame = CGRect(x: x, y: 2, width: 18, height: 18)
        addSubview(b)
    }

    override func mouseDown(with event: NSEvent) {
        guard let id = elementID else { return }
        list?.select(id, additive: !event.modifierFlags.isDisjoint(with: [.shift, .command]))
    }

    @objc private func eyeTapped()  { if let id = elementID { list?.toggleHidden(id) } }
    @objc private func upTapped()   { if let id = elementID { list?.move(id, delta: -1) } }
    @objc private func downTapped() { if let id = elementID { list?.move(id, delta: 1) } }
}
