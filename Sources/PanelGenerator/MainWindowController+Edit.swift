import AppKit
import UniformTypeIdentifiers
import PanelKit
import PanelCanvas

// Window: edit-menu commands.

extension MainWindowController {

    // MARK: Edit commands

    @objc func pgUndo(_ sender: Any?) {
        canvas.edits.undo()
        reloadInspector()
        markDirty()
    }

    @objc func pgRedo(_ sender: Any?) {
        canvas.edits.redo()
        reloadInspector()
        markDirty()
    }

    @objc func pgDuplicate(_ sender: Any?) { canvas.duplicateSelection() }
    // Standard NSText-matching selector names, deliberately not pg-prefixed
    // and wired with a nil target (AppDelegate.swift) -- see the note above
    // validateMenuItem for why.
    @objc func copy(_ sender: Any?) { canvas.copySelection() }
    @objc func cut(_ sender: Any?) { canvas.cutSelection() }
    @objc func paste(_ sender: Any?) { canvas.paste() }

    @objc func delete(_ sender: Any?) { canvas.deleteSelection() }

    @objc func pgSelectAll(_ sender: Any?) { canvas.selectAllElements() }

    @objc func pgFront(_ sender: Any?) { canvas.bringToFront() }

    @objc func pgBack(_ sender: Any?) { canvas.sendToBack() }

    @objc func pgScrews(_ sender: Any?) { canvas.insertCornerScrews() }

    @objc func pgMakeWidget(_ sender: Any?) {
        guard !canvas.selection.isEmpty else { return }
        inspector.makeWidgetFromMenu()
    }

    @objc func pgLabelSelection(_ sender: Any?) {
        guard !canvas.selection.isEmpty else { return }
        inspector.labelSelectionFromMenu()
    }

    /// Turn the labels drawn on the panel into component identifiers.
    ///
    /// A label and an identifier are different fields — one is drawn, the other
    /// reaches the generated enum — and a panel can be fully labelled while
    /// every component is still unnamed. On a labelled panel the label is what
    /// you would have typed anyway.
    @objc func pgNameFromLabels(_ sender: Any?) {
        let result = canvas.nameFromLabels(within: labelReach)
        reloadInspector()
        let alert = NSAlert()
        alert.messageText = result.named == 0
            ? "No labels close enough to name anything"
            : "Named \(result.named) component\(result.named == 1 ? "" : "s") from their labels"
        alert.informativeText = result.skipped == 0
            ? "Every component in scope had a label beside it."
            : "\(result.skipped) had no label within \(Geo.fmt(PanelMetrics.mm(labelReach))) mm. "
                + "Label them, or set their Identifier by hand."
        alert.runModal()
    }

    /// Copy identifiers from another panel, matched on the label beside each
    /// control.
    ///
    /// What a redesign needs: the same module in a new layout has the same
    /// controls in different places, so position cannot pair them — but the
    /// label under a knob says what the knob is in both panels, and that is
    /// what the identifier records. It also means two documents never have to
    /// be open at once.
    @objc func pgAdoptIdentifiers(_ sender: Any?) {
        let open = NSOpenPanel()
        open.canChooseDirectories = false
        open.allowsMultipleSelection = false
        open.allowedContentTypes = [UTType(filenameExtension: PanelDocument.fileExtension) ?? .json,
                                    UTType(filenameExtension: "cpp") ?? .sourceCode]
        open.message = "Take identifiers from this panel or module source, matching by label."
        guard open.runModal() == .OK, let url = open.url else { return }

        do {
            let source: PanelDocument
            if url.pathExtension == PanelDocument.fileExtension {
                source = try PanelDocument.load(from: url)
            } else {
                // A module's source carries both halves too: the identifiers in
                // its create* calls and the labels in its helper calls.
                let text = try String(contentsOf: url, encoding: .utf8)
                let siblings = (try? FileManager.default.contentsOfDirectory(
                    at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil))?
                    .filter { ["h", "hpp", "hh"].contains($0.pathExtension.lowercased()) }
                    .prefix(24) ?? []
                var doc = PanelDocument()
                doc.elements = CppImport.outcome(
                    from: text,
                    headers: siblings.compactMap { try? String(contentsOf: $0, encoding: .utf8) }).elements
                source = doc
            }

            let result = canvas.adoptIdentifiers(from: source, within: labelReach)
            reloadInspector()

            let alert = NSAlert()
            let n = result.adopted.count
            alert.messageText = n == 0
                ? "Nothing matched"
                : "Adopted \(n) identifier\(n == 1 ? "" : "s") from \(url.lastPathComponent)"

            var lines: [String] = []
            // Every loose match is listed. A redesign renames as it goes, so
            // some of these are guesses — and a guess you cannot see is worse
            // than no guess at all.
            let loose = result.adopted.filter { $0.kind != .exact }
            if !loose.isEmpty {
                lines.append("Matched by abbreviation, worth checking:\n"
                    + loose.map { "   \($0.label) → \($0.identifier)" }.joined(separator: "\n"))
            }
            if !result.unmatched.isEmpty {
                lines.append("No match for:\n"
                    + result.unmatched.prefix(14).map { "   \($0)" }.joined(separator: "\n")
                    + (result.unmatched.count > 14 ? "\n   …" : ""))
                lines.append("Those keep the identifier they had. A control the old panel did not "
                    + "have is expected; a label that was reworded is not — rename it to match, "
                    + "or set Identifier by hand.")
            }
            if lines.isEmpty { lines.append("Every control matched exactly.") }
            alert.informativeText = lines.joined(separator: "\n\n")
            alert.runModal()
        } catch {
            showError("Could not read that panel", error)
        }
    }


    /// Bring a panel's contents back inside its edges after it has been
    /// narrowed. Offers the two operations that are defensible; anything
    /// cleverer is a design decision, and this is not the thing to make it.
    @objc func pgFitToPanel(_ sender: Any?) {
        let strays = canvas.document.strayComponents()

        let alert = NSAlert()
        alert.messageText = strays.isEmpty
            ? "Everything is already inside the panel"
            : "\(strays.count) component\(strays.count == 1 ? " sits" : "s sit") outside the "
              + "\(canvas.document.widthHP)HP panel"
        alert.informativeText = "Rack draws a component exactly where the code puts it, so one beyond "
            + "the module's edge cannot be seen or clicked — while still occupying a parameter.\n\n"
            + "Both moves are undoable, and neither changes any size: a component's size comes from "
            + "Rack's own artwork."
        alert.addButton(withTitle: "Fit")
        alert.addButton(withTitle: "Cancel")

        let box = NSView(frame: CGRect(x: 0, y: 0, width: 380, height: 78))
        let modes = PanelDocument.FitMode.allCases
        var buttons: [NSButton] = []
        for (i, mode) in modes.enumerated() {
            let b = NSButton(radioButtonWithTitle: mode.displayName, target: nil, action: nil)
            b.frame = CGRect(x: 0, y: 52 - CGFloat(i) * 24, width: 380, height: 20)
            b.state = i == 0 ? .on : .off
            box.addSubview(b)
            buttons.append(b)
        }
        let marginLabel = NSTextField(labelWithString: "Margin (px)")
        marginLabel.font = NSFont.systemFont(ofSize: 11)
        marginLabel.frame = CGRect(x: 0, y: 2, width: 80, height: 18)
        let margin = NSTextField(string: "6")
        margin.frame = CGRect(x: 84, y: 0, width: 56, height: 22)
        margin.toolTip = "Kept clear inside every edge. Rack's own panels leave room for the screws."
        box.addSubview(marginLabel)
        box.addSubview(margin)
        alert.accessoryView = box

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let picked = modes[buttons.firstIndex { $0.state == .on } ?? 0]
        let inset = CGFloat(Double(margin.stringValue) ?? 6)
        let moved = canvas.fitToPanel(picked, margin: max(0, inset))
        reloadInspector()

        let done = NSAlert()
        done.messageText = moved == 0 ? "Nothing needed moving" : "Moved \(moved) elements"
        done.informativeText = canvas.document.strayComponents().isEmpty
            ? "Every component is inside the panel."
            : "\(canvas.document.strayComponents().count) still sit outside — the panel may be too "
              + "narrow for the layout at any spacing. Widen it, or move those by hand."
        done.runModal()
    }

    @objc func pgBindPrimitives(_ sender: Any?) {
        let bound = canvas.bindPrimitives()
        reloadInspector()
        guard bound == 0 else { return }
        let alert = NSAlert()
        alert.messageText = "Nothing left to bind."
        alert.informativeText = "Every jack, knob, fader, button and LED already has a role. "
            + "Shapes, text and screws stay as artwork on purpose — set those by hand if you want them bound."
        alert.runModal()
    }
}
