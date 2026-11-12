import AppKit
import UniformTypeIdentifiers
import PanelKit
import PanelCanvas

// Window: zoom, snap, grids and theme preview.

extension MainWindowController {

    // MARK: View commands

    @objc func pgZoomIn(_ sender: Any?)   { canvas.zoom *= 1.25 }
    @objc func pgZoomOut(_ sender: Any?)  { canvas.zoom /= 1.25 }
    @objc func pgZoomActual(_ sender: Any?) { canvas.zoom = 1 }

    @objc func pgZoomFit(_ sender: Any?) {
        guard let sv = scrollView else { return }
        let visible = sv.contentSize
        let size = canvas.document.pixelSize
        guard visible.width > 10, visible.height > 10 else { return }
        canvas.zoom = min(visible.width / size.width, visible.height / size.height) * 0.92
        sv.documentView?.scroll(NSPoint(x: 0, y: 0))
    }

    @objc func pgSetSnapStep(_ sender: Any?) {
        guard let mi = sender as? NSMenuItem else { return }
        canvas.snapStep = CGFloat(mi.tag) / 100
        canvas.snapMode = .uniform
        canvas.snapEnabled = true
        canvas.needsDisplay = true
    }

    /// Serge's non-uniform row/column grid (see `SergeGrid`) -- the default
    /// snap mode. Placement and movement snap element *centres* to it;
    /// resize handles and arrow-key nudging keep using the uniform step.
    @objc func pgSetSergeGrid(_ sender: Any?) {
        canvas.snapMode = .sergeGrid
        canvas.snapEnabled = true
        canvas.needsDisplay = true
    }

    @objc func pgToggleSnapToElements(_ sender: Any?) {
        canvas.snapToElements.toggle()
        UserDefaults.standard.set(!canvas.snapToElements, forKey: "SnapToElementsOff")
    }

    @objc func pgToggleInspectorUnits(_ sender: Any?) {
        InspectorView.useMillimetres.toggle()
        reloadInspector()
    }

    /// The Paperface 50 grid (see `PaperfaceGrid`).
    @objc func pgSetPaperfaceGrid(_ sender: Any?) {
        canvas.snapMode = .paperfaceGrid
        canvas.snapEnabled = true
        canvas.needsDisplay = true
    }

    /// Paperface column pitch in HP, stored in the document; selecting one
    /// also switches to the Paperface grid so the change is visible at once.
    @objc func pgSetPaperfacePitch(_ sender: Any?) {
        guard let mi = sender as? NSMenuItem else { return }
        let hp = mi.tag
        canvas.mutateDocument(name: "Paperface Column Pitch") {
            var spec = $0.paperfaceGrid ?? PaperfaceGridSpec()
            spec.columnHP = hp == PaperfaceGrid.defaultColumnHP ? nil : hp
            $0.paperfaceGrid = spec.isDefault ? nil : spec
        }
        pgSetPaperfaceGrid(sender)
    }

    /// Rows (origin, pitch, count), column pitch and quarter positions for
    /// this document's Paperface grid. Lengths take mm, or px with a "px"
    /// suffix — "22px" and "57.6px" are as good as 7.45 and 19.507.
    @objc func pgPaperfaceGridSettings(_ sender: Any?) {
        let r = PaperfaceGrid.resolved(canvas.document)
        let alert = NSAlert()
        alert.messageText = "Paperface Grid"
        alert.informativeText = "Main rows start at the origin and repeat at the pitch; half rows fall "
            + "between them. Put the main rows on object centres (the default, measured) or on the cell "
            + "lines (then the centres are the half rows). Lengths in mm, or add \"px\"."
        func field(_ v: String, _ y: CGFloat) -> NSTextField {
            let f = NSTextField(frame: CGRect(x: 120, y: y, width: 120, height: 22)); f.stringValue = v; return f
        }
        func caption(_ s: String, _ y: CGFloat) -> NSTextField {
            let l = NSTextField(labelWithString: s); l.frame = CGRect(x: 0, y: y + 3, width: 116, height: 16); return l
        }
        let box = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 176))
        let origin = field(String(format: "%.3f", Double(r.originMM)), 148)
        let pitch = field(String(format: "%.3f", Double(r.pitchMM)), 120)
        let rows = field(String(r.rows), 92)
        let cols = field(String(r.columnHP), 64)
        let quarters = NSButton(checkboxWithTitle: "Quarter positions", target: nil, action: nil)
        quarters.frame = CGRect(x: 118, y: 34, width: 160, height: 20)
        quarters.state = r.quarters ? .on : .off
        let reset = NSButton(checkboxWithTitle: "Reset to measured defaults", target: nil, action: nil)
        reset.frame = CGRect(x: 118, y: 8, width: 200, height: 20)
        for (c, y) in [("First row", 148), ("Row pitch", 120), ("Rows", 92), ("Column pitch HP", 64)] as [(String, CGFloat)] {
            box.addSubview(caption(c, y))
        }
        [origin, pitch, rows, cols, quarters, reset].forEach(box.addSubview)
        alert.accessoryView = box
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        func mm(_ s: String) -> CGFloat? {
            let t = s.lowercased().replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
            if t.hasSuffix("px"), let v = Double(t.dropLast(2).trimmingCharacters(in: .whitespaces)) {
                return CGFloat(v) * PanelMetrics.mmPerPixel
            }
            return Double(t.replacingOccurrences(of: "mm", with: "").trimmingCharacters(in: .whitespaces)).map { CGFloat($0) }
        }
        var spec = PaperfaceGridSpec()
        if reset.state != .on {
            if let v = mm(origin.stringValue), abs(v - PaperfaceGrid.firstRowMM) > 0.0005 { spec.rowOriginMM = v }
            if let v = mm(pitch.stringValue), v > 1, abs(v - PaperfaceGrid.rowPitchMM) > 0.0005 { spec.rowPitchMM = v }
            if let v = Int(rows.stringValue), v != PaperfaceGrid.rowCount { spec.rowCount = min(max(v, 1), 24) }
            if let v = Int(cols.stringValue), v != PaperfaceGrid.defaultColumnHP {
                spec.columnHP = min(max(v, PaperfaceGrid.columnHPRange.lowerBound), PaperfaceGrid.columnHPRange.upperBound)
            }
            if quarters.state == .on { spec.quarters = true }
        }
        canvas.mutateDocument(name: "Paperface Grid") { $0.paperfaceGrid = spec.isDefault ? nil : spec }
        pgSetPaperfaceGrid(sender)
    }

    /// Toggles `PanelDocument.sergeGridOuterHalfSteps`: one further half-step
    /// row beyond the top and bottom of Serge's standard 5-row grid, for
    /// real panels that push a row of LEDs/jacks that far out (e.g. the
    /// GTS's top LED row).
    ///
    /// Turning it ON also switches to Serge Grid and enables snapping, same
    /// as selecting "Serge Grid" itself -- the checkbox is meant to have an
    /// immediate, visible effect on the next drag, not just flip a flag that
    /// only matters if Serge Grid happens to already be the active mode.
    /// (Custom Grid's own half-positions checkbox gets this for free: it
    /// lives inside the "Custom Grid..." dialog, which already switches to
    /// Custom Grid on confirm. This one is a standalone menu item, so it has
    /// to do that switch itself.) Turning it OFF leaves the active mode
    /// alone -- there's no equivalent reason to switch *away* from Serge
    /// Grid just because this particular option was turned off.
    @objc func pgToggleSergeOuterHalfStep(_ sender: Any?) {
        let on = !canvas.document.sergeGridOuterHalfSteps
        canvas.mutateDocument(name: "Serge Grid Outer Half-Step") {
            $0.sergeGridOuterHalfSteps = on
        }
        if on {
            // Applies to the Paperface grid as well; stay on it if active.
            if canvas.snapMode != .paperfaceGrid { canvas.snapMode = .sergeGrid }
            canvas.snapEnabled = true
        }
        canvas.needsDisplay = true
    }

    /// Switches what the canvas previews (View ▸ Theme) -- Dark always
    /// matches a document's own untouched colours; Light substitutes
    /// `PanelDocument.lightBackground`/`inkLight` wherever an element opted
    /// in via "Follows panel ink". Editing-only: never written to the
    /// document, and has no visible effect on a panel that isn't themed
    /// (`PanelDocument.isThemed`), since its light and dark colours are then
    /// identical by construction.
    @objc func pgSetThemePreview(_ sender: Any?) {
        guard let tag = (sender as? NSMenuItem)?.tag, let variant = ThemeVariant(rawValue: tag == 1 ? "light" : "dark") else { return }
        canvas.themePreview = variant
        canvas.needsDisplay = true
    }

    /// A plain, editable N x M grid (see `CustomGrid`) for panels whose real
    /// layout doesn't follow Serge's standardised one -- e.g. an imported
    /// module that genuinely has 5 columns, not Serge's 4. Always opens the
    /// dialog, even when custom grid is already the active mode, so the
    /// divisions stay easy to revisit rather than a one-time setup step.
    @objc func pgSetCustomGrid(_ sender: Any?) {
        let doc = canvas.document
        let alert = NSAlert()
        alert.messageText = "Custom Grid"
        alert.informativeText = "Divide the panel evenly into this many columns and rows. "
            + "Rows stay clear of the corner screws top and bottom. Placement and "
            + "movement will snap element centres to the intersections."
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")

        let box = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 106))
        let colsLabel = NSTextField(labelWithString: "Columns")
        colsLabel.frame = CGRect(x: 0, y: 84, width: 96, height: 18)
        let cols = NSTextField(string: String(max(1, doc.customGridColumns)))
        cols.frame = CGRect(x: 100, y: 82, width: 60, height: 22)
        let rowsLabel = NSTextField(labelWithString: "Rows")
        rowsLabel.frame = CGRect(x: 0, y: 56, width: 96, height: 18)
        let rows = NSTextField(string: String(max(1, doc.customGridRows)))
        rows.frame = CGRect(x: 100, y: 54, width: 60, height: 22)
        let half = NSButton(checkboxWithTitle: "Half positions (Serge-style)",
                            target: nil, action: nil)
        half.frame = CGRect(x: 0, y: 26, width: 240, height: 18)
        half.font = NSFont.systemFont(ofSize: 11)
        half.state = doc.customGridHalfPositions ? .on : .off
        half.toolTip = "Adds a half row between each pair of rows and half-lane columns "
            + "between each pair of columns, on the diagonal cross between four main "
            + "grid points -- Serge's own convention for where LEDs, switches and "
            + "jacks (never knobs) sit, generalised to this grid's own division count."
        let finer = NSButton(checkboxWithTitle: "Finer positions (quarter-step)",
                            target: nil, action: nil)
        finer.frame = CGRect(x: 0, y: 4, width: 240, height: 18)
        finer.font = NSFont.systemFont(ofSize: 11)
        finer.state = doc.customGridFinerPositions ? .on : .off
        finer.toolTip = "Adds a further pair of snap positions at 1/4 and 3/4 of every "
            + "cell, on every row and column -- unlike half positions, not tied to any "
            + "particular row or column kind. For layouts where two components flank a "
            + "half position instead of sharing it, e.g. a RISE/FALL pair's independent "
            + "EXPO switches either side of the half-lane column their shared CYCLE "
            + "switch already occupies."
        box.addSubview(colsLabel)
        box.addSubview(cols)
        box.addSubview(rowsLabel)
        box.addSubview(rows)
        box.addSubview(half)
        box.addSubview(finer)
        alert.accessoryView = box
        alert.window.initialFirstResponder = cols

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let n = max(1, Int(cols.stringValue) ?? doc.customGridColumns)
        let m = max(1, Int(rows.stringValue) ?? doc.customGridRows)
        let halfOn = half.state == .on
        let finerOn = finer.state == .on
        canvas.mutateDocument(name: "Custom Grid") {
            $0.customGridColumns = n
            $0.customGridRows = m
            $0.customGridHalfPositions = halfOn
            $0.customGridFinerPositions = finerOn
        }
        canvas.snapMode = .customGrid
        canvas.snapEnabled = true
        canvas.needsDisplay = true
    }

    @objc func pgDeselectAll(_ sender: Any?) { canvas.setSelection([]) }

    @objc func pgToggleSnap(_ sender: Any?) {
        canvas.snapEnabled.toggle()
        canvas.needsDisplay = true
    }
}
