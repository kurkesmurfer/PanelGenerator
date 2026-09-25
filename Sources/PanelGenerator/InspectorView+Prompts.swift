import AppKit
import PanelKit
import PanelCanvas

// Inspector: label and widget prompts.

extension InspectorView {

    /// Promote the selection to a composed widget. Asks for the struct name,
    /// because that name reaches the generated C++ and the asset filenames and
    /// is not something to invent silently.
    /// Same prompt, reached from the Edit menu.
    func makeWidgetFromMenu() { promptMakeWidget() }
    func labelSelectionFromMenu() { promptLabelSelection() }

    /// Label every selected component in one action.
    ///
    /// The settings are asked for once and applied to the whole selection —
    /// that is the whole point. Labelling twenty-five controls one text box at
    /// a time is what this replaces, and a size that turns out wrong is fixed
    /// on all of them at once because the new labels come back selected.
    func promptLabelSelection() {
        guard let cv = canvas, !cv.selection.isEmpty else { return }

        // Anything already carrying a name; the rest can only be labelled once
        // it has one, and saying so up front beats producing eight labels for
        // a selection of twelve without explanation.
        let named = cv.document.elements.filter {
            cv.selection.contains($0.id) && $0.kind != .text
                && cv.document.labelText(for: $0, uppercase: true, spaceUnderscores: true) != nil
        }.count

        let alert = NSAlert()
        alert.messageText = "Label \(named) of \(cv.selection.count) selected element\(cv.selection.count == 1 ? "" : "s")"
        alert.informativeText = named == 0
            ? "None of the selection carries a name yet. Set Identifier in the inspector, or use "
              + "Name Sequentially, and run this again."
            : "One text label per named component, placed the same way for all of them. "
              + "Running it again on the same controls replaces these labels rather than adding a second set."
        alert.addButton(withTitle: "Create Labels")
        alert.addButton(withTitle: "Cancel")

        // Frame-placed, top-down, like the rest of this inspector: the alert's
        // accessory view is not under Auto Layout.
        let lineH: CGFloat = 26
        let box = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 5 * lineH))
        func place(_ v: NSView, row: CGFloat, x: CGFloat, w: CGFloat, h: CGFloat = 22) {
            v.frame = CGRect(x: x, y: box.bounds.height - (row + 1) * lineH + (lineH - h) / 2,
                             width: w, height: h)
            box.addSubview(v)
        }
        func caption(_ t: String, row: CGFloat) {
            let l = NSTextField(labelWithString: t)
            l.font = NSFont.systemFont(ofSize: 11)
            l.alignment = .right
            place(l, row: row, x: 0, w: 76, h: 16)
        }

        caption("Placement", row: 0)
        let placement = NSPopUpButton(frame: .zero, pullsDown: false)
        placement.addItems(withTitles: LabelPlacement.allCases.map(\.displayName))
        placement.selectItem(at: LabelPlacement.allCases.firstIndex(of: labelPlacement) ?? 1)
        place(placement, row: 0, x: 82, w: 110, h: 24)

        caption("Gap", row: 1)
        let gapField = NSTextField(string: Geo.fmt(labelGap))
        gapField.toolTip = "Distance from the control's edge to the label, in panel pixels "
            + "(\(Geo.fmt(PanelMetrics.mm(labelGap))) mm)."
        place(gapField, row: 1, x: 82, w: 60)
        let gapNote = NSTextField(labelWithString: "px")
        gapNote.font = NSFont.systemFont(ofSize: 11)
        gapNote.textColor = .secondaryLabelColor
        place(gapNote, row: 1, x: 146, w: 24, h: 16)

        caption("Size", row: 2)
        let sizeField = NSTextField(string: Geo.fmt(labelSize))
        sizeField.toolTip = "Jack labels are 2.0–2.5 mm (6–7.5 px), knob labels 2.5–3.0. "
            + "Anything under about 2 mm disappears on MetaModule's 240 px faceplate."
        place(sizeField, row: 2, x: 82, w: 60)
        let bold = NSButton(checkboxWithTitle: "Bold", target: nil, action: nil)
        bold.state = labelBold ? .on : .off
        place(bold, row: 2, x: 150, w: 70)
        let well = NSColorWell(frame: .zero)
        well.color = (labelColour ?? defaultLabelColour(in: cv.document)).nsColor
        place(well, row: 2, x: 226, w: 60, h: 22)

        let upper = NSButton(checkboxWithTitle: "Uppercase", target: nil, action: nil)
        upper.state = labelUppercase ? .on : .off
        place(upper, row: 3, x: 82, w: 140)

        let spaces = NSButton(checkboxWithTitle: "Underscores as spaces", target: nil, action: nil)
        spaces.state = labelSpaces ? .on : .off
        spaces.toolTip = "CUTOFF_FREQ is how the generated enum must read; \"CUTOFF FREQ\" is how the panel should."
        place(spaces, row: 4, x: 82, w: 210)

        alert.accessoryView = box
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        labelPlacement = LabelPlacement.allCases[max(0, min(LabelPlacement.allCases.count - 1,
                                                           placement.indexOfSelectedItem))]
        labelGap = CGFloat(Double(gapField.stringValue.replacingOccurrences(of: ",", with: ".")) ?? Double(labelGap))
        labelSize = max(4, CGFloat(Double(sizeField.stringValue.replacingOccurrences(of: ",", with: ".")) ?? Double(labelSize)))
        labelBold = bold.state == .on
        labelUppercase = upper.state == .on
        labelSpaces = spaces.state == .on
        labelColour = ColorSpec(color: well.color)

        let result = cv.labelSelection(placement: labelPlacement, gap: labelGap,
                                       fontSize: labelSize, bold: labelBold,
                                       uppercase: labelUppercase, spaceUnderscores: labelSpaces,
                                       colour: labelColour ?? .hex("#E8E8F0"))
        if result.created == 0 && result.skipped > 0 {
            let none = NSAlert()
            none.messageText = "Nothing to label"
            none.informativeText = "\(result.skipped) selected element\(result.skipped == 1 ? " carries" : "s carry") "
                + "no name yet. Set Identifier in the inspector, or use Name Sequentially."
            none.runModal()
        }
        scheduleRebuild()
    }

    /// Match labels already on the panel rather than imposing a colour: a panel
    /// with a house text colour should keep it without a trip to the well.
    private func defaultLabelColour(in doc: PanelDocument) -> ColorSpec {
        var counts: [ColorSpec: Int] = [:]
        for el in doc.elements where el.kind == .text { counts[el.fill, default: 0] += 1 }
        return counts.max { a, b in
            a.value == b.value ? a.key.hexString < b.key.hexString : a.value < b.value
        }?.key ?? .hex("#E8E8F0")
    }

    func promptMakeWidget() {
        guard let cv = canvas, !cv.selection.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Make a widget from \(cv.selection.count) element\(cv.selection.count == 1 ? "" : "s")"
        alert.informativeText = "The parts become one control: the artwork exports as its own SVG, "
            + "and a matching C++ struct is generated. Tick \"Rotates with value\" on the parts "
            + "that should turn, such as a knob's indicator."
        alert.addButton(withTitle: "Make Widget")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(string: "LcarsKnob")
        field.frame = CGRect(x: 0, y: 26, width: 260, height: 22)
        let roles = NSPopUpButton(frame: CGRect(x: 0, y: 0, width: 260, height: 24))
        let choices: [ComponentRole] = [.param, .input, .output, .custom]
        roles.addItems(withTitles: choices.map(\.displayName))

        let box = NSView(frame: CGRect(x: 0, y: 0, width: 260, height: 52))
        box.addSubview(field)
        box.addSubview(roles)
        alert.accessoryView = box

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let role = choices[max(0, min(choices.count - 1, roles.indexOfSelectedItem))]
        cv.makeWidget(name: CodeGen.cppIdentifier(name, fallback: "CustomWidget"), role: role)
        scheduleRebuild()
    }
}
