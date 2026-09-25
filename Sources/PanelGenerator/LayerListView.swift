import AppKit

/// Bottom of the left sidebar: z-ordered element list, top layer first.
/// Click selects · ⇧/⌘-click extends · ◉/○ toggles visibility · ▲▼ reorder.
///
/// An NSTableView rather than hand-placed rows. The previous version laid rows
/// out at fixed offsets inside a 190 pt frame with no scroller, so everything
/// past the seventh element was drawn outside the view and unreachable — and it
/// tore down and recreated four views per row on every mouse-drag frame,
/// because `onChange` fires from the document's didSet.
///
/// Two things keep it cheap now: reloads are skipped while a canvas gesture is
/// in flight (a drag changes coordinates, not the list), and even then the
/// table only reloads when the list's *shape* actually changed.
final class LayerListView: NSView {

    weak var canvas: CanvasView? {
        didSet { rebuild() }
    }

    private let scroll = NSScrollView()
    private let table = NSTableView()
    private let header = NSTextField(labelWithString: "LAYERS")

    /// Top layer first, i.e. `document.elements` reversed.
    private var rows: [PanelElement] = []
    private var signature: [String] = []
    private var didBuild = false
    private var pending = false
    private var flushScheduled = false
    private var syncingSelection = false

    override var isFlipped: Bool { true }

    // MARK: Construction

    private func buildIfNeeded() {
        guard !didBuild else { return }
        didBuild = true

        header.font = NSFont.boldSystemFont(ofSize: 9)
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)

        table.headerView = nil
        table.style = .plain
        table.rowHeight = 22
        table.gridStyleMask = []
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.backgroundColor = ColorSpec.hex("#2B2B33").nsColor
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("layer"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self

        // Right-click delete, as an alternative to plain Backspace (see
        // `owns(_:)` below for the Backspace path itself). AppKit selects the
        // clicked row first if it wasn't already part of the selection, same
        // as the standard Finder/table convention, so this always acts on
        // whatever the click actually landed on.
        let menu = NSMenu()
        let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteSelectedRows), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)
        table.menu = menu

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = ColorSpec.hex("#2B2B33").nsColor
        addSubview(scroll)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            header.heightAnchor.constraint(equalToConstant: 13),

            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    // MARK: Refresh

    /// Kept as `rebuild()` so the window controller's calls are unchanged, but
    /// it no longer rebuilds anything directly — it marks the list dirty and
    /// lets the flush decide when there is something worth doing.
    func rebuild() {
        buildIfNeeded()
        pending = true
        scheduleFlush()
    }

    private func scheduleFlush() {
        guard pending, !flushScheduled else { return }
        // A drag moves elements; it does not change the layer list. Wait for
        // mouseUp, which fires onSelectionChange and brings us back here.
        guard canvas?.isGestureActive != true else { return }
        flushScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flushScheduled = false
            self.pending = false
            self.flush()
        }
    }

    private func flush() {
        guard let cv = canvas else { return }
        let newRows = Array(cv.document.elements.reversed())
        let newSignature = newRows.map {
            "\($0.id.uuidString)|\($0.name)|\($0.isHidden == true)|\($0.groupID?.uuidString ?? "")|\($0.kind.rawValue)"
        }
        rows = newRows
        if newSignature != signature {
            signature = newSignature
            header.stringValue = "LAYERS — \(rows.count)"
            table.reloadData()
        }
        syncSelection(from: cv)
    }

    private func syncSelection(from cv: CanvasView) {
        var wanted = IndexSet()
        for (i, el) in rows.enumerated() where cv.selection.contains(el.id) { wanted.insert(i) }
        guard wanted != table.selectedRowIndexes else { return }
        syncingSelection = true
        table.selectRowIndexes(wanted, byExtendingSelection: false)
        syncingSelection = false
        if let first = wanted.first { table.scrollRowToVisible(first) }
    }

    // MARK: Row actions

    func toggleHidden(_ id: UUID) {
        guard let cv = canvas else { return }
        var els = cv.document.elements
        guard let i = els.firstIndex(where: { $0.id == id }) else { return }
        els[i].isHidden = els[i].isHidden == true ? nil : true
        let hiding = els[i].isHidden == true
        cv.apply(elements: els, name: hiding ? "Hide Element" : "Show Element")
    }

    @objc private func deleteSelectedRows() {
        canvas?.deleteSelection()
    }

    /// `delta` is in list terms: +1 moves the element one row up the list,
    /// which means one step later in `elements` — later is drawn on top.
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

// MARK: - Table data & delegate

extension LayerListView: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let id = NSUserInterfaceItemIdentifier("LayerRow")
        let view = tableView.makeView(withIdentifier: id, owner: self) as? LayerRowView
            ?? {
                let v = LayerRowView()
                v.identifier = id
                return v
            }()
        view.configure(element: rows[row], list: self)
        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !syncingSelection, let cv = canvas else { return }
        var ids = Set<UUID>()
        for i in table.selectedRowIndexes where rows.indices.contains(i) {
            ids.formUnion(cv.groupMembers(rows[i].id))   // groups select as one unit
        }
        cv.setSelection(ids)
    }
}

// MARK: - One row

/// Visibility toggle, name, up/down reorder. Built once and reconfigured on
/// reuse — the table recycles these.
final class LayerRowView: NSView {

    private let eye = NSButton()
    private let badge = NSTextField(labelWithString: "")
    private let label = NSTextField(labelWithString: "")
    private let up = NSButton()
    private let down = NSButton()

    private var elementID: UUID?
    private weak var list: LayerListView?
    private var didBuild = false

    private func buildIfNeeded() {
        guard !didBuild else { return }
        didBuild = true

        func style(_ b: NSButton, _ title: String, _ action: Selector) {
            b.title = title
            b.target = self
            b.action = action
            b.isBordered = false
            b.font = NSFont.systemFont(ofSize: 9)
            b.translatesAutoresizingMaskIntoConstraints = false
            addSubview(b)
        }
        style(eye, "◉", #selector(eyeTapped))
        style(up, "▲", #selector(upTapped))
        style(down, "▼", #selector(downTapped))

        badge.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold)
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 3
        badge.translatesAutoresizingMaskIntoConstraints = false
        addSubview(badge)

        label.font = NSFont.systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)

        NSLayoutConstraint.activate([
            eye.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            eye.centerYAnchor.constraint(equalTo: centerYAnchor),
            eye.widthAnchor.constraint(equalToConstant: 18),

            badge.leadingAnchor.constraint(equalTo: eye.trailingAnchor, constant: 2),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.widthAnchor.constraint(equalToConstant: 15),
            badge.heightAnchor.constraint(equalToConstant: 13),

            label.leadingAnchor.constraint(equalTo: badge.trailingAnchor, constant: 4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: up.leadingAnchor, constant: -4),

            up.trailingAnchor.constraint(equalTo: down.leadingAnchor),
            up.centerYAnchor.constraint(equalTo: centerYAnchor),
            up.widthAnchor.constraint(equalToConstant: 18),

            down.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            down.centerYAnchor.constraint(equalTo: centerYAnchor),
            down.widthAnchor.constraint(equalToConstant: 18),
        ])
    }

    func configure(element: PanelElement, list: LayerListView) {
        buildIfNeeded()
        self.elementID = element.id
        self.list = list

        // Role at a glance. Binding is otherwise invisible unless you select an
        // element and find the Component section, which is exactly how it stays
        // undiscovered.
        let isWidget = element.widgetSource == .custom && !element.customWidgetName.isEmpty
        badge.stringValue = isWidget ? "W" : element.role.badge
        if badge.stringValue.isEmpty {
            badge.layer?.backgroundColor = NSColor.clear.cgColor
        } else {
            let tint = isWidget
                ? ColorSpec.hex("#ffff00")
                : ColorSpec.hex(element.role.helperFill ?? "#808080")
            badge.textColor = NSColor.black.withAlphaComponent(0.85)
            badge.layer?.backgroundColor = tint.nsColor.withAlphaComponent(0.85).cgColor
        }

        let hidden = element.isHidden == true
        eye.title = hidden ? "○" : "◉"
        let base = element.name.isEmpty ? element.kind.displayName : element.name
        label.stringValue = element.groupID != nil ? "▸ " + base : base
        label.textColor = hidden ? .secondaryLabelColor : .labelColor
        // A bound component is not artwork; mark it so the two are tellable
        // apart in a list where everything otherwise looks the same.
        if element.role.isComponent {
            label.toolTip = "\(element.role.displayName) · \(element.identifierStem)\(element.role.enumSuffix)"
        } else {
            label.toolTip = nil
        }
    }

    @objc private func eyeTapped()  { if let id = elementID { list?.toggleHidden(id) } }
    @objc private func upTapped()   { if let id = elementID { list?.move(id, delta: 1) } }
    @objc private func downTapped() { if let id = elementID { list?.move(id, delta: -1) } }
}
