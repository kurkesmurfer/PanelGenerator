import AppKit
import UniformTypeIdentifiers
import PanelKit
import PanelCanvas

// Window: importing SVG artwork and module C++.

extension MainWindowController {

    // MARK: Import

    /// Read an existing panel SVG — someone else's module, or your own earlier
    /// artwork — either as a tracing template or as editable elements.
    @objc func pgImportSVG(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.svg]
        panel.message = "Import a panel SVG as a tracing template or as editable artwork."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let choice = NSAlert()
        choice.messageText = "Import \(url.lastPathComponent)"
        choice.informativeText = "A template is reference only: drawn faintly, not clickable on the canvas, "
            + "and never exported — trace over it and delete it when you are done. Imported artwork is "
            + "editable, but only rectangles and ellipses come back as parametric elements; everything "
            + "else arrives as a path you can move, scale and recolour but not reshape."
        choice.addButton(withTitle: "Import")
        choice.addButton(withTitle: "Cancel")

        let box = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 82))
        let mode = NSPopUpButton(frame: CGRect(x: 0, y: 56, width: 320, height: 24))
        mode.addItems(withTitles: ["As tracing template", "As editable artwork"])
        let components = NSButton(checkboxWithTitle: "Read a helper.py components layer, if present",
                                  target: nil, action: nil)
        components.state = .on
        components.frame = CGRect(x: 0, y: 30, width: 320, height: 20)
        let resize = NSButton(checkboxWithTitle: "Take the panel's size and background from the file",
                              target: nil, action: nil)
        resize.state = canvas.document.elements.isEmpty ? .on : .off
        resize.frame = CGRect(x: 0, y: 6, width: 320, height: 20)
        box.addSubview(mode); box.addSubview(components); box.addSubview(resize)
        choice.accessoryView = box
        guard choice.runModal() == .alertFirstButtonReturn else { return }

        var options = SVGImport.Options()
        options.asTemplate = mode.indexOfSelectedItem == 0
        options.bindComponents = components.state == .on
        options.adoptBackground = resize.state == .on

        do {
            let data = try Data(contentsOf: url)
            let outcome = try SVGImport.outcome(from: data, options: options)
            var doc = canvas.document
            if resize.state == .on {
                doc.widthHP = outcome.widthHP
                doc.format = outcome.format
                if let bg = outcome.background { doc.background = bg }
            }
            if !options.asTemplate, doc.name.isEmpty || doc.name == "Untitled" {
                // Name the document after the import too, when it has no name
                // of its own -- otherwise every import must be retitled by
                // hand. A re-imported PanelGenerator export recovers its
                // exact name from its own header comment; anything else
                // falls back to the file's name on disk.
                doc.name = outcome.suggestedName ?? url.deletingPathExtension().lastPathComponent
            }
            doc.elements.append(contentsOf: outcome.elements)
            canvas.applyDocument(doc, name: "Import SVG")
            canvas.setSelection(options.asTemplate ? [] : Set(outcome.elements.map(\.id)))
            reloadInspector()
            report(outcome, from: url, resized: resize.state == .on)
        } catch {
            showError("Could not import that SVG", error)
        }
    }

    /// Read a module's C++ and rebuild its components: positions, widget types
    /// and identifiers all at once. The panel SVG beside it supplies the
    /// artwork, which is why this offers to import it in the same pass.
    @objc func pgImportModuleCode(_ sender: Any?) {
        let open = NSOpenPanel()
        open.canChooseDirectories = false
        open.allowsMultipleSelection = false
        open.allowedContentTypes = [UTType(filenameExtension: "cpp") ?? .sourceCode,
                                    UTType(filenameExtension: "cc") ?? .sourceCode,
                                    UTType(filenameExtension: "hpp") ?? .sourceCode,
                                    .sourceCode]
        open.message = "Choose the source holding the ModuleWidget constructor."
        guard open.runModal() == .OK, let url = open.url else { return }

        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            // Constants are routinely declared in a sibling header — a panel
            // laid out on a named grid is unreadable without them.
            let siblings = (try? FileManager.default.contentsOfDirectory(
                at: url.deletingLastPathComponent(), includingPropertiesForKeys: [.fileSizeKey]))?
                .filter { ["h", "hpp", "hh"].contains($0.pathExtension.lowercased()) }
                .prefix(24) ?? []
            let headers = siblings.compactMap { try? String(contentsOf: $0, encoding: .utf8) }

            // Read once to learn which panel the widget sets, then again
            // knowing how big that panel is. Rack's own module template
            // positions its screws from box.size.x, and a module widget's box
            // is whatever setPanel gave it — so the second pass is what makes
            // the two right-hand screws of nearly every plugin readable.
            let first = CppImport.outcome(from: source, headers: headers)
            let panelURL = first.panelResource.flatMap { resolveResource($0, near: url) }
            let panelSize = panelURL
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap { SVGImport.panelSize(from: $0) }
            let outcome = panelSize == nil
                ? first
                : CppImport.outcome(from: source, headers: headers, panelSize: panelSize)

            // The plugin slug is not in the source — it lives in plugin.json,
            // beside it or one level up. It names the generated widget library
            // and its namespace, so importing without it produces a plugin
            // called MyPlugin.
            let plugin = pluginManifest(near: url)
            let answer = confirmModuleImport(outcome, source: url, panel: panelURL)
            guard answer.proceed else { return }
            let artworkURL = answer.includeArtwork ? panelURL : nil

            var doc = canvas.document
            var report = outcome.warnings

            // Artwork first, so the components land on top of it.
            if let artworkURL {
                do {
                    var options = SVGImport.Options()
                    options.bindComponents = false      // the C++ is the authority here
                    let art = try SVGImport.outcome(from: try Data(contentsOf: artworkURL), options: options)
                    doc.widthHP = art.widthHP
                    doc.format = art.format
                    if let bg = art.background { doc.background = bg }
                    doc.elements.append(contentsOf: art.elements)
                    report.append(contentsOf: art.warnings)
                } catch {
                    report.append("The panel \(artworkURL.lastPathComponent) could not be read: "
                        + error.localizedDescription)
                }
            }
            if let hp = outcome.widthHP { doc.widthHP = hp }
            if let plugin { doc.pluginSlug = plugin }
            if let slug = outcome.moduleSlug {
                doc.moduleSlug = slug
                // Name the document after the module too, when it has no name
                // of its own. Otherwise an emitted panel reports itself as
                // "Untitled" for the rest of its life.
                if doc.name.isEmpty || doc.name == "Untitled" { doc.name = slug }
            }
            doc.elements.append(contentsOf: outcome.elements)

            canvas.applyDocument(doc, name: "Import Module Code")
            canvas.setSelection(Set(outcome.elements.map(\.id)))
            reloadInspector()

            let done = NSAlert()
            let n = outcome.elements.count
            done.messageText = "Imported \(n) component\(n == 1 ? "" : "s")"
            done.informativeText = report.isEmpty
                ? "Everything in the file was understood."
                : report.joined(separator: "\n\n")
            done.runModal()
        } catch {
            showError("Could not read that source file", error)
        }
    }

    /// Confirm before overwriting, and say what was found — including the
    /// tallies, because "42 components" is the number you check against the
    /// module you are looking at.
    private func confirmModuleImport(_ outcome: CppImport.Outcome, source: URL,
                                     panel: URL?) -> (proceed: Bool, includeArtwork: Bool) {
        let params = outcome.elements.filter { $0.role == .param }.count
        let inputs = outcome.elements.filter { $0.role == .input }.count
        let outputs = outcome.elements.filter { $0.role == .output }.count
        let lights = outcome.elements.filter { $0.role == .light }.count

        let alert = NSAlert()
        alert.messageText = "Import \(outcome.elements.count) components from \(source.lastPathComponent)?"
        var lines = ["\(params) params · \(inputs) inputs · \(outputs) outputs · \(lights) lights"]
        if let slug = outcome.moduleSlug { lines.append("Module slug: \(slug)") }
        if let plugin = pluginManifest(near: source) {
            lines.append("Plugin slug: \(plugin), from plugin.json — it names the generated widget library.")
        }
        if panel == nil, let named = outcome.panelResource {
            lines.append("The source names \(named), which is not where this reader looked. "
                + "Import it separately with File ▸ Import SVG.")
        }
        if !canvas.document.elements.isEmpty {
            lines.append("This adds to the panel you have open rather than replacing it.")
        }
        alert.informativeText = lines.joined(separator: "\n")
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")

        // Only offered when the artwork was actually found. Ticked by default:
        // components with no panel behind them are a list of coordinates, and
        // the point of reading the source is to get the module back whole.
        var artwork: NSButton? = nil
        if let panel {
            let check = NSButton(checkboxWithTitle: "Also import \(panel.lastPathComponent) as artwork",
                                 target: nil, action: nil)
            check.state = .on
            check.toolTip = "Untick if you have already imported the panel — otherwise you get it twice."
            check.frame = CGRect(x: 0, y: 0, width: 320, height: 20)
            alert.accessoryView = check
            artwork = check
        }

        let proceed = alert.runModal() == .alertFirstButtonReturn
        return (proceed, artwork?.state == .on)
    }

    /// The plugin's slug, from the plugin.json Rack requires every plugin to
    /// have. Looked for beside the source and one level up, the same two places
    /// the panel artwork is.
    private func pluginManifest(near source: URL) -> String? {
        let dir = source.deletingLastPathComponent()
        for candidate in [dir.appendingPathComponent("plugin.json"),
                          dir.deletingLastPathComponent().appendingPathComponent("plugin.json")] {
            guard let data = try? Data(contentsOf: candidate),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let slug = json["slug"] as? String, !slug.isEmpty else { continue }
            return slug
        }
        return nil
    }

    /// `res/Muse.svg` as written in the source, found on disk. Plugins put the
    /// source in the root or in src/, so both are worth a look.
    private func resolveResource(_ relative: String, near source: URL) -> URL? {
        let dir = source.deletingLastPathComponent()
        let candidates = [
            dir.appendingPathComponent(relative),
            dir.deletingLastPathComponent().appendingPathComponent(relative),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// What came in, and what did not. An importer that silently drops half a
    /// panel is worse than one that refuses: you would find out by noticing a
    /// hole in your own drawing a week later.
    private func report(_ outcome: SVGImport.Outcome, from url: URL, resized: Bool) {
        let alert = NSAlert()
        let count = outcome.elements.count
        alert.messageText = "Imported \(count) element\(count == 1 ? "" : "s")"
        var lines: [String] = []
        lines.append(String(format: "%@ measures %.0f × %.0f px (%.1f × %.1f mm) — %d HP %@.",
                            url.lastPathComponent,
                            outcome.sourceSize.width, outcome.sourceSize.height,
                            PanelMetrics.mm(outcome.sourceSize.width),
                            PanelMetrics.mm(outcome.sourceSize.height),
                            outcome.widthHP, outcome.format.rawValue))
        if !resized {
            lines.append("The panel kept its own size; the import may not line up with it.")
        }
        lines.append(contentsOf: outcome.warnings)
        alert.informativeText = lines.joined(separator: "\n\n")
        alert.runModal()
    }

    func loadIntoCanvas(_ doc: PanelDocument, url: URL?) {
        suppressDirty = true
        canvas.beginLoad()
        canvas.document = doc
        canvas.endLoad()
        suppressDirty = false
        fileURL = url
        isDirty = false
        reloadInspector()
        updateTitle()
        pgZoomFit(nil)
    }
}
