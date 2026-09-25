import AppKit
import PanelKit
import PanelCanvas

// Inspector: component binding, colour groups and alignment.

extension InspectorView {

    /// Frame-based button rows — this view is frame-managed; NSStackView's
    /// Auto Layout sizing leaves its arranged buttons invisible here.
    func buttonRow(_ titles: [String], handlers actions: [() -> Void], columns: Int) {
        let w = (contentW - CGFloat(columns - 1) * 6) / CGFloat(columns)
        for (i, t) in titles.enumerated() {
            let b = makeButton(t, handler: actions[i])
            b.frame = CGRect(x: pad + CGFloat(i) * (w + 6), y: cursorY, width: w, height: 22)
            addSubview(b)
        }
        cursorY += 28
    }


    func buildComponentSection(for el: PanelElement) {
        section("Component")
        let weakCanvas = canvas

        label("Role")
        let role = NSPopUpButton(frame: .zero, pullsDown: false)
        role.addItems(withTitles: ComponentRole.allCases.map(\.displayName))
        role.selectItem(at: ComponentRole.allCases.firstIndex(of: el.role) ?? 0)
        role.font = NSFont.systemFont(ofSize: 11)
        addControl(role, width: 170)
        handlers.append { sender in
            guard let p = sender as? NSPopUpButton else { return }
            let i = max(0, min(ComponentRole.allCases.count - 1, p.indexOfSelectedItem))
            let picked = ComponentRole.allCases[i]
            weakCanvas?.mutateSelection("Component Role") { $0.role = picked }
        }

        // "Identifier", not "Name". This is the C++ enum stem — CUTOFF becomes
        // CUTOFF_PARAM in the generated code — and it is neither the layer name
        // in the list nor the label drawn on the panel. Three different things
        // called Name was one too many.
        label("Identifier")
        let nm = makeField(value: el.enumName, placeholder: el.identifierStem)
        nm.toolTip = "The name this control has in the generated C++: \"\(el.identifierStem)\" becomes "
            + "\(el.identifierStem)\(el.role.enumSuffix). Not the label drawn on the panel, and not "
            + "the layer name. Empty means it is derived from the layer name, which will change if "
            + "you rename the layer."
        addControl(nm)
        handlers.append { sender in
            guard let f = sender as? NSTextField else { return }
            weakCanvas?.mutateSelection("Component Identifier") { $0.enumName = f.stringValue }
        }

        label("Artwork")
        let src = NSPopUpButton(frame: .zero, pullsDown: false)
        src.addItems(withTitles: WidgetSource.allCases.map(\.displayName))
        src.selectItem(at: WidgetSource.allCases.firstIndex(of: el.widgetSource) ?? 0)
        src.font = NSFont.systemFont(ofSize: 11)
        addControl(src, width: 170)
        handlers.append { sender in
            guard let p = sender as? NSPopUpButton else { return }
            let i = max(0, min(WidgetSource.allCases.count - 1, p.indexOfSelectedItem))
            let picked = WidgetSource.allCases[i]
            weakCanvas?.mutateSelection("Widget Source") { $0.widgetSource = picked }
        }

        label("Rack type")
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

        label("Custom struct")
        let custom = makeField(value: el.customWidgetName, placeholder: "LcarsKnob")
        addControl(custom)
        handlers.append { sender in
            guard let f = sender as? NSTextField else { return }
            weakCanvas?.mutateSelection("Custom Widget") { $0.customWidgetName = f.stringValue }
        }

        // Composed widgets: which parts turn decides the bg/fg split, and it
        // is per-part, so it lives on the element rather than on the widget.
        if let cv = canvas, cv.document.widgetMembers(of: el).count > 1 || el.groupID != nil {
            let turns = makeCheck("Rotates with value", on: el.rotatesWithValue)
            turns.toolTip = "Parts ticked here go into the widget's -fg file, which Rack "
                + "rotates; everything else is the static background. Only knobs turn."
            addControl(turns)
            let weakCanvas = canvas
            handlers.append { sender in
                guard let b = sender as? NSButton else { return }
                weakCanvas?.mutateSelection("Rotating Part") { $0.rotatesWithValue = b.state == .on }
            }
        }

        // Millimetres are the unit mm2px() and MetaModule's x_mm both speak, so
        // show them next to the px fields rather than making you convert.
        let mm = el.centerMM
        var note = "Centre \(Geo.fmt(mm.x)) × \(Geo.fmt(mm.y)) mm"
        if el.role.isComponent {
            note += el.widgetSource == .stock
                ? " · size comes from Rack's own artwork; resizing here only moves the guide."
                : " · exported as res/components/\(el.widgetClass).svg at this size."
        } else {
            note += " · artwork, stays in the exported panel."
        }
        let hint = NSTextField(labelWithString: note)
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.textColor = NSColor.secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 3
        hint.frame = CGRect(x: pad, y: cursorY, width: contentW, height: 40)
        addSubview(hint)
        cursorY += 44
    }

    func buildColourSection(for cv: CanvasView) {
        let fills = cv.document.colourGroups(ids: cv.selection, strokes: false)
        let strokes = cv.document.colourGroups(ids: cv.selection, strokes: true)
        guard !fills.isEmpty || !strokes.isEmpty else { return }

        section("Colours — \(cv.selection.count) selected")

        func rows(_ groups: [(colour: ColorSpec, ids: [UUID])], isStroke: Bool, tag: String) {
            // A selection with dozens of distinct colours would push everything
            // else off the panel; the long tail is not what this is for.
            let shown = groups.prefix(12)
            for (i, group) in shown.enumerated() {
                label("\(group.colour.hexString) ×\(group.ids.count)")
                let well = makeColorWell(group.colour)
                well.toolTip = "\(group.ids.count) element\(group.ids.count == 1 ? "" : "s") "
                    + "share this \(isStroke ? "stroke" : "fill")."
                addControl(well, width: 70)
                let ids = group.ids
                let weakCanvas = canvas
                handlers.append { sender in
                    guard let w = sender as? NSColorWell else { return }
                    weakCanvas?.setColour(ColorSpec(color: w.color), ids: ids, strokes: isStroke,
                                          name: "Recolour \(tag)\(i)")
                }
            }
            if groups.count > shown.count {
                let note = NSTextField(labelWithString: "+ \(groups.count - shown.count) more colours")
                note.font = NSFont.systemFont(ofSize: 10)
                note.textColor = NSColor.secondaryLabelColor
                note.frame = CGRect(x: pad, y: cursorY, width: contentW, height: 14)
                addSubview(note)
                cursorY += 18
            }
        }

        rows(fills, isStroke: false, tag: "f")
        if !strokes.isEmpty {
            let header = NSTextField(labelWithString: "STROKES")
            header.font = NSFont.systemFont(ofSize: 9, weight: .bold)
            header.textColor = ColorSpec.hex("#9A9AB0").nsColor
            header.frame = CGRect(x: pad, y: cursorY + 2, width: contentW, height: 13)
            addSubview(header)
            cursorY += 18
            rows(strokes, isStroke: true, tag: "s")
        }
    }

    /// One element cannot be aligned to itself, so it always falls back to the
    /// panel however the scope is set.
    func applyAlign(_ mode: String) {
        guard let cv = canvas else { return }
        cv.alignSelection(mode, to: cv.selection.count > 1 ? alignTarget : "panel")
    }
}
