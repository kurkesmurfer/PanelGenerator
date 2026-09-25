import AppKit
import PanelKit

// Inspector: the layer section.

extension InspectorView {

    /// Rebuild on the next pass rather than immediately: a control's own
    /// handler must not tear down the control while it is still being used.
    func scheduleRebuild() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let cv = self.canvas else { return }
            self.rebuild(document: cv.document, canvas: cv)
        }
    }

    func buildLayerSection() {
        guard let cv = canvas, !cv.selection.isEmpty else { return }

        // An element you can select but cannot grab reads as a bug. Say what it
        // is, and offer the way out — otherwise the only route back is to
        // import the file again and lose everything drawn since.
        let selected = cv.document.elements.filter { cv.selection.contains($0.id) }
        let templates = selected.filter { $0.isTemplate == true }.count
        if templates > 0 {
            section("Template")
            let note = NSTextField(wrappingLabelWithString:
                "\(templates) of \(selected.count) selected \(templates == 1 ? "is" : "are") tracing "
                + "template artwork: drawn faintly, not clickable on the canvas, and never exported. "
                + "Make it editable to keep it.")
            note.font = NSFont.systemFont(ofSize: 10)
            note.textColor = ColorSpec.hex("#9A9AB0").nsColor
            note.maximumNumberOfLines = 5
            note.frame = CGRect(x: pad, y: cursorY, width: contentW, height: 58)
            addSubview(note)
            cursorY += 62
            buttonRow(["Make Editable"], handlers: [
                { [weak self] in
                    self?.canvas?.setTemplate(false)
                    self?.scheduleRebuild()
                },
            ], columns: 1)
        } else {
            section("Template")
            let note = NSTextField(labelWithString: "Turn the selection into tracing reference.")
            note.font = NSFont.systemFont(ofSize: 10)
            note.textColor = ColorSpec.hex("#9A9AB0").nsColor
            note.frame = CGRect(x: pad, y: cursorY, width: contentW, height: 14)
            addSubview(note)
            cursorY += 18
            buttonRow(["Make Template"], handlers: [
                { [weak self] in
                    self?.canvas?.setTemplate(true)
                    self?.scheduleRebuild()
                },
            ], columns: 1)
        }

        // Colours across the selection. A group of glyphs, a bank of faders or
        // a row of knobs is usually several elements sharing one colour, and
        // recolouring them one at a time through the single-element Fill well
        // is the tedium this removes. One well per distinct colour, so a mixed
        // selection stays editable rather than being flattened to one colour.
        if cv.selection.count > 1 {
            buildColourSection(for: cv)
        }

        // One set of align buttons with an explicit scope. Two separate rows
        // labelled identically (L/CX/R/T/M/B for the selection, and again for
        // the panel) meant reaching for "top" and getting the panel's top edge.
        section("Align")
        let multi = cv.selection.count > 1

        label("Relative to")
        let scope = NSPopUpButton(frame: .zero, pullsDown: false)
        scope.addItems(withTitles: ["Selection", "Panel"])
        scope.selectItem(at: (multi && alignTarget == "sel") ? 0 : 1)
        scope.isEnabled = multi
        scope.font = NSFont.systemFont(ofSize: 11)
        scope.toolTip = multi
            ? "Selection: T moves everything to the topmost selected edge, L to the leftmost, and so on. Panel: to the panel's own edges and centre lines."
            : "Only one element is selected, so there is nothing to align it to but the panel."
        addControl(scope, width: 120)
        handlers.append { [weak self] sender in
            guard let self, let p = sender as? NSPopUpButton else { return }
            self.alignTarget = p.indexOfSelectedItem == 1 ? "panel" : "sel"
        }

        // The buttons read alignTarget when clicked, so changing the scope does
        // not have to rebuild the inspector out from under the popup.
        buttonRow(["L", "CX", "R", "T", "M", "B"], handlers: [
            { [weak self] in self?.applyAlign("L") },
            { [weak self] in self?.applyAlign("CX") },
            { [weak self] in self?.applyAlign("R") },
            { [weak self] in self?.applyAlign("T") },
            { [weak self] in self?.applyAlign("CY") },
            { [weak self] in self?.applyAlign("B") },
        ], columns: 6)

        if multi {
            label("Distribute by")
            let distBy = NSPopUpButton(frame: .zero, pullsDown: false)
            distBy.addItems(withTitles: ["Gap", "Center"])
            distBy.selectItem(at: distributeMode == "center" ? 1 : 0)
            distBy.font = NSFont.systemFont(ofSize: 11)
            distBy.toolTip = "Gap: equal edge-to-edge spacing (right for whitespace between "
                + "same-ish-sized elements). Center: equal centre-to-centre spacing regardless "
                + "of each element's own size (right when mixed-size elements -- e.g. two "
                + "switches between two differently-sized knobs -- need to sit at even "
                + "fractions of the span, not even gaps)."
            addControl(distBy, width: 120)
            handlers.append { [weak self] sender in
                guard let self, let p = sender as? NSPopUpButton else { return }
                self.distributeMode = p.indexOfSelectedItem == 1 ? "center" : "gap"
            }
            buttonRow(["Dist X", "Dist Y"], handlers: [
                { [weak self] in cv.distributeSelection("X", by: self?.distributeMode ?? "gap") },
                { [weak self] in cv.distributeSelection("Y", by: self?.distributeMode ?? "gap") },
            ], columns: 2)
        }

        section("Arrange")
        buttonRow(["Front", "Back", "Duplicate", "Delete"], handlers: [
            { [weak self] in self?.canvas?.bringToFront() },
            { [weak self] in self?.canvas?.sendToBack() },
            { [weak self] in self?.canvas?.duplicateSelection() },
            { [weak self] in self?.canvas?.deleteSelection() },
        ], columns: 4)
        buttonRow(["Group", "Ungroup"], handlers: [
            { [weak self] in self?.canvas?.groupSelection() },
            { [weak self] in self?.canvas?.ungroupSelection() },
        ], columns: 2)
        buttonRow(["Make Widget…", "Label…"], handlers: [
            { [weak self] in self?.promptMakeWidget() },
            { [weak self] in self?.promptLabelSelection() },
        ], columns: 2)
        buttonRow(["Copy", "Cut", "Paste"], handlers: [
            { [weak self] in self?.canvas?.copySelection() },
            { [weak self] in self?.canvas?.cutSelection() },
            { [weak self] in self?.canvas?.paste() },
        ], columns: 3)
    }
}
