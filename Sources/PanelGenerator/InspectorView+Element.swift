import AppKit
import PanelKit

// Inspector: the selected element (frame, fill, stroke, swatches) and multi-selection.

extension InspectorView {

    func buildElementSection(for el: PanelElement) {
        section("Element — \(el.kind.displayName)")

        func posSizeFields() {
            let fields: [(String, WritableKeyPath<PanelElement, CGFloat>)] = [
                ("X", \.x), ("Y", \.y), ("W", \.w), ("H", \.h),
            ]
            // Two per row
            for pair in stride(from: 0, to: fields.count, by: 2) {
                let rowViews: [NSView] = []
                _ = rowViews
                var built: [(NSTextField, WritableKeyPath<PanelElement, CGFloat>)] = []
                for j in pair..<min(pair + 2, fields.count) {
                    let (title, kp) = fields[j]
                    label(title, xOffset: j % 2 == 1 ? (contentW - labelW) / 2 : 0)
                    let f = makeField(value: Geo.fmt(el[keyPath: kp]))
                    f.frame = CGRect(x: pad + labelW + (j % 2 == 1 ? (contentW - labelW) / 2 + 4 : 0),
                                     y: cursorY, width: (contentW - labelW) / 2 - 4, height: rowH)
                    f.tag = handlers.count
                    f.target = self
                    f.action = #selector(controlAction(_:))
                    addSubview(f)
                    let weakCanvas = canvas
                    handlers.append { sender in
                        if let v = (sender as? NSTextField)?.stringValue,
                           let d = Double(v.replacingOccurrences(of: ",", with: ".")) {
                            weakCanvas?.mutateSelection("Position/Size") { e in
                                e[keyPath: kp] = CGFloat(d)
                            }
                        }
                    }
                    built.append((f, kp))
                }
                cursorY += rowH + gap
            }
        }
        posSizeFields()

        label("Rotation")
        let rot = makeSlider(min: -180, max: 180, value: Double(el.rotation))
        let rotField = makeField(value: Geo.fmt(el.rotation))
        addPair(rot, rotField, split: 0.72)
        handlers.append { [weak self] sender in
            guard let self else { return }
            let raw: CGFloat
            if let s = sender as? NSSlider {
                raw = CGFloat(s.doubleValue)
            } else if let v = self.parse(sender) {
                raw = CGFloat(v)
            } else { return }
            let v = Self.niceAngle(raw)   // also collapses the near-zero case cleanly
            self.canvas?.mutateSelection("Rotate") { $0.rotation = v }
            rot.doubleValue = Double(v)
            rotField.stringValue = Geo.fmt(v)
        }

        label("Fill")
        addColorControl(el.fill) { [weak self] spec in
            self?.canvas?.mutateSelection("Fill") { $0.fill = spec }
        }

        label("Theme")
        let inkCheck = makeCheck("Follows panel ink", on: el.followsInk)
        inkCheck.toolTip = "Draw in the document's ink colour for whichever theme is active "
            + "(View ▸ Theme) instead of this element's own Fill above -- e.g. a label that "
            + "should read white on a dark panel and black on a light one. Fill is kept, not "
            + "overwritten, so turning this off falls back to it exactly as it was."
        addControl(inkCheck)
        handlers.append { [weak self] sender in
            guard let self, let b = sender as? NSButton else { return }
            self.canvas?.mutateSelection("Follows Ink") { $0.followsInk = (b.state == .on) }
        }

        label("")
        let paperCheck = makeCheck("Follows panel background", on: el.followsPaper)
        paperCheck.toolTip = "Draw in the document's background (paper) colour instead of this "
            + "element's own Fill above -- for a shape that should blend into the panel rather "
            + "than read as content, e.g. a patch obscuring part of a delineation box's boundary "
            + "line. Not the same as \"Follows panel ink\": ink and paper are deliberately "
            + "near-opposites, so following ink here would make the shape stand out instead of "
            + "disappear. Fill is kept, not overwritten, so turning this off falls back to it."
        addControl(paperCheck)
        handlers.append { [weak self] sender in
            guard let self, let b = sender as? NSButton else { return }
            self.canvas?.mutateSelection("Follows Background") { $0.followsPaper = (b.state == .on) }
        }

        // Swatch bank: every design language's named colours (Styles/).
        addSwatchBank(current: el.fill)

        label("Stroke")
        let strokeWell = makeColorWell(el.stroke ?? ColorSpec.hex("#FFFFFF"))
        let none = makeCheck("none", on: el.stroke == nil)
        addPair(strokeWell, none)
        let weakCanvas = canvas
        handlers.append { sender in
            if let cw = sender as? NSColorWell {
                weakCanvas?.mutateSelection("Stroke") { $0.stroke = ColorSpec(color: cw.color) }
            } else if let b = sender as? NSButton {
                let noneChecked = b.state == .on
                weakCanvas?.mutateSelection("Stroke") {
                    $0.stroke = noneChecked ? nil : ColorSpec.hex("#FFFFFF")
                }
            }
        }

        label("Width")
        let sw = makeField(value: Geo.fmt(el.strokeWidth))
        addControl(sw)
        handlers.append { [weak self] sender in
            guard let self else { return }
            if let v = self.cgf(sender) {
                self.canvas?.mutateSelection("Stroke Width") { $0.strokeWidth = max(0.25, v) }
            }
        }
    }

    private func addSwatchBank(current: ColorSpec) {
        let swatchesPerRow = 10
        let cell: CGFloat = 17
        let spacing: CGFloat = 3
        for (i, swatch) in DesignLanguage.allSwatches.enumerated() {
            let row = i / swatchesPerRow
            let col = i % swatchesPerRow
            let b = NSButton(frame: CGRect(x: pad + labelW + CGFloat(col) * (cell + spacing),
                                           y: cursorY + CGFloat(row) * (cell + spacing),
                                           width: cell, height: cell))
            b.title = ""
            b.isBordered = false
            b.wantsLayer = true
            b.layer?.backgroundColor = swatch.color.nsColor.cgColor
            b.layer?.cornerRadius = 3.5
            b.layer?.borderWidth = current == swatch.color ? 1.6 : 0.6
            b.layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
            b.toolTip = swatch.name
            let idx = handlers.count
            let color = swatch.color
            let weakCanvas = canvas
            b.target = self
            b.action = #selector(controlAction(_:))
            b.tag = idx
            handlers.append { _ in
                weakCanvas?.mutateSelection("Fill") { $0.fill = color }
            }
        }
        let rows = (DesignLanguage.allSwatches.count + swatchesPerRow - 1) / swatchesPerRow
        cursorY += CGFloat(rows) * (cell + spacing) + gap
    }

    /// The properties worth writing to a whole selection at once: size,
    /// rotation, colour. Position deliberately not — setting X across a
    /// selection stacks it into a column, and Align already does the useful
    /// version of that.
    func buildSharedSection(for el: PanelElement, count: Int) {
        section("\(count) × \(el.kind.displayName)")
        let weakCanvas = canvas

        for (title, keyPath) in [("W", \PanelElement.w), ("H", \PanelElement.h)] {
            plabel(title, keyPath)
            let field = makeField(value: Geo.fmt(el[keyPath: keyPath]))
            addControl(field)
            handlers.append { sender in
                guard let f = sender as? NSTextField,
                      let v = Double(f.stringValue.replacingOccurrences(of: ",", with: ".")) else { return }
                weakCanvas?.mutateSelection("Size") { $0[keyPath: keyPath] = CGFloat(v) }
            }
        }

        plabel("Rotation", \.rotation)
        let rot = makeSlider(min: -180, max: 180, value: Double(el.rotation))
        let rotField = makeField(value: Geo.fmt(el.rotation))
        addPair(rot, rotField, split: 0.72)
        handlers.append { [weak self] sender in
            guard let self else { return }
            let raw: CGFloat
            if let s = sender as? NSSlider {
                raw = CGFloat(s.doubleValue)
            } else if let v = self.parse(sender) {
                raw = CGFloat(v)
            } else { return }
            let v = Self.niceAngle(raw)
            weakCanvas?.mutateSelection("Rotate") { $0.rotation = v }
            rot.doubleValue = Double(v)
            rotField.stringValue = Geo.fmt(v)
        }

        plabel("Fill", \.fill)
        addColorControl(el.fill) { spec in
            weakCanvas?.mutateSelection("Fill") { $0.fill = spec }
        }

        label("Theme")
        let inkCheck = makeCheck("Follows panel ink", on: el.followsInk)
        addControl(inkCheck)
        handlers.append { sender in
            guard let b = sender as? NSButton else { return }
            weakCanvas?.mutateSelection("Follows Ink") { $0.followsInk = (b.state == .on) }
        }
        label("")
        let paperCheck = makeCheck("Follows panel background", on: el.followsPaper)
        addControl(paperCheck)
        handlers.append { sender in
            guard let b = sender as? NSButton else { return }
            weakCanvas?.mutateSelection("Follows Background") { $0.followsPaper = (b.state == .on) }
        }
        addSwatchBank(current: el.fill)

        // Role and naming for the whole selection. These used to appear only
        // for a single element, which meant turning six jacks into outputs was
        // six separate trips through the inspector.
        section("Components — \(count) selected")

        plabel("Role", \.role)
        let roles = NSPopUpButton(frame: .zero, pullsDown: false)
        roles.addItems(withTitles: ComponentRole.allCases.map(\.displayName))
        roles.selectItem(at: ComponentRole.allCases.firstIndex(of: el.role) ?? 0)
        roles.font = NSFont.systemFont(ofSize: 11)
        addControl(roles, width: 170)
        handlers.append { sender in
            guard let p = sender as? NSPopUpButton else { return }
            let picked = ComponentRole.allCases[max(0, min(ComponentRole.allCases.count - 1, p.indexOfSelectedItem))]
            weakCanvas?.mutateSelection("Component Role") { $0.role = picked }
        }

        label("Name prefix")
        let prefix = makeField(value: "", placeholder: "IN → IN_1, IN_2 …")
        prefix.toolTip = "Numbers the selection in reading order — top row first, left to "
            + "right. Identifiers are what make the generated enum readable as IN_3 rather "
            + "than JACK_3_5_MM_7."
        addControl(prefix)
        handlers.append { [weak self] sender in
            guard let f = sender as? NSTextField, !f.stringValue.isEmpty else { return }
            weakCanvas?.nameSelectionSequentially(prefix: f.stringValue)
            self?.scheduleRebuild()
        }

        if !el.kind.stockWidgetChoices.isEmpty {
            plabel("Rack type", \.stockWidget)
            let combo = NSComboBox(frame: .zero)
            combo.font = NSFont.systemFont(ofSize: 11)
            combo.addItems(withObjectValues: el.kind.stockWidgetChoices)
            combo.stringValue = el.stockWidget
            combo.completes = true
            addControl(combo)
            handlers.append { sender in
                guard let cb = sender as? NSComboBox else { return }
                weakCanvas?.mutateSelection("Rack Widget") { $0.stockWidget = cb.stringValue }
            }
        }
    }
}
