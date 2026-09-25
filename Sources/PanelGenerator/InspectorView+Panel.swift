import AppKit
import PanelKit

// Inspector: the Panel section (size, format, theme, slugs, export units).

extension InspectorView {

    func buildPanelSection() {
        section("Panel")

        label("Name")
        let name = makeField(value: document.name)
        addControl(name)
        handlers.append { [weak self] sender in
            guard let self, let f = sender as? NSTextField else { return }
            self.canvas?.mutateDocument(name: "Panel Name") { $0.name = f.stringValue.isEmpty ? "Untitled" : f.stringValue }
        }

        label("Width (HP)")
        let hp = makeField(value: String(document.widthHP))
        addControl(hp)
        handlers.append { [weak self] sender in
            guard let self else { return }
            let v = Int(self.parse(sender) ?? 8)
            self.canvas?.mutateDocument(name: "Panel Width") {
                $0.widthHP = min(max(v, PanelMetrics.minPanelWidthHP), PanelMetrics.maxPanelWidthHP)
                sender.stringValue = String($0.widthHP)
            }
        }

        label("Height")
        let pop = NSPopUpButton(frame: .zero, pullsDown: false)
        pop.addItems(withTitles: PanelFormat.allCases.map(\.rawValue))
        pop.selectItem(withTitle: document.format.rawValue)
        pop.font = NSFont.systemFont(ofSize: 11)
        addControl(pop, width: 90)
        handlers.append { [weak self] sender in
            guard let self, let p = sender as? NSPopUpButton,
                  let fmt = PanelFormat(rawValue: p.titleOfSelectedItem ?? "") else { return }
            self.canvas?.mutateDocument(name: "Panel Height") { $0.format = fmt }
        }

        label("Background")
        addColorControl(document.background) { [weak self] spec in
            self?.canvas?.mutateDocument(name: "Background") { $0.background = spec }
        }

        // Theme facility: a document only becomes themed once a light
        // background is actually set -- the "Enable" checkbox just gives
        // that first light value (a lightened guess from the dark one,
        // rather than plain white) so turning it on always leaves something
        // sane to then adjust, rather than an empty/undefined state.
        label("Theme")
        let themeOn = makeCheck("Light variant", on: document.isThemed)
        themeOn.toolTip = "Gives this panel a light colour variant -- View ▸ Theme previews it, "
            + "and --emit writes it alongside the dark one automatically as <slug>-light.svg. "
            + "Elements marked \"Follows panel ink\" (per-element Theme checkbox) swap between "
            + "Ink (dark) and Ink (light) below; everything else stays the same in both."
        addControl(themeOn)
        handlers.append { [weak self] sender in
            guard let self, let b = sender as? NSButton else { return }
            self.canvas?.mutateDocument(name: "Enable Theme") { doc in
                if b.state == .on {
                    if doc.lightBackground == nil { doc.lightBackground = doc.background.lightened(0.92) }
                } else {
                    doc.lightBackground = nil
                }
            }
            self.scheduleRebuild()   // the two colour wells below only make sense once this is on
        }

        if document.isThemed {
            label("Light bg")
            addColorControl(document.lightBackground ?? document.background.lightened(0.92)) { [weak self] spec in
                self?.canvas?.mutateDocument(name: "Light Background") { $0.lightBackground = spec }
            }

            label("Ink (dark)")
            addColorControl(document.inkDark) { [weak self] spec in
                self?.canvas?.mutateDocument(name: "Ink (Dark)") { $0.inkDark = spec }
            }

            label("Ink (light)")
            addColorControl(document.inkLight) { [weak self] spec in
                self?.canvas?.mutateDocument(name: "Ink (Light)") { $0.inkLight = spec }
            }
        }

        label("Plugin slug")
        let pslug = makeField(value: document.pluginSlug, placeholder: "MyPlugin")
        pslug.toolTip = "The plugin that will contain this module — its directory name and "
            + "the top-level \"slug\" in plugin.json. Not the brand: brand is a separate "
            + "display field. One plugin holds many modules."
        
        addControl(pslug)
        handlers.append { [weak self] sender in
            guard let self, let f = sender as? NSTextField else { return }
            // Corrected on entry rather than flagged afterwards. An invalid
            // slug has no useful meaning — it cannot be a filename and cannot
            // be a C++ identifier — so letting one exist only defers the same
            // edit to a warning you have to act on later.
            let clean = CodeGen.slugSuggestion(f.stringValue)
            f.stringValue = clean
            self.canvas?.mutateDocument(name: "Plugin Slug") { $0.pluginSlug = clean }
            self.scheduleRebuild()
        }

        label("Module slug")
        let mslug = makeField(value: document.moduleSlug, placeholder: "MyModule")
        mslug.toolTip = "Permanent once a patch has been saved with this module — "
            + "changing it later breaks every patch that uses it."
        addControl(mslug)
        handlers.append { [weak self] sender in
            guard let self, let f = sender as? NSTextField else { return }
            let clean = CodeGen.slugSuggestion(f.stringValue)
            f.stringValue = clean
            self.canvas?.mutateDocument(name: "Module Slug") { $0.moduleSlug = clean }
            self.scheduleRebuild()   // so the names below follow
        }

        label("Widget ns")
        let wns = makeField(value: document.widgetNamespace, placeholder: "museui")
        wns.toolTip = "Namespace to wrap generated custom widget structs in. "
            + "Leave empty to put them at file scope."
        addControl(wns)
        handlers.append { [weak self] sender in
            guard let self, let f = sender as? NSTextField else { return }
            self.canvas?.mutateDocument(name: "Widget Namespace") { $0.widgetNamespace = f.stringValue }
        }

        // What these two names actually produce. Plugin and module are both
        // "the slug" until you can see that one names a shared widget library
        // and the other names this panel's own files.
        let names = [
            "Plugin \(document.pluginSlug) →",
            "   \(CodeGen.widgetsHeaderName(document)), namespace \(CodeGen.uiNamespace(document))",
            "Module \(document.moduleSlug) →",
            "   res/\(document.moduleSlug).svg, \(CodeGen.moduleIdentifier(document))_panel.hpp,",
            "   namespace \(CodeGen.moduleIdentifier(document))Panel",
        ].joined(separator: "\n")
        let plan = NSTextField(labelWithString: names)
        plan.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        plan.textColor = ColorSpec.hex("#8A8AA0").nsColor
        plan.lineBreakMode = .byWordWrapping
        plan.maximumNumberOfLines = 6
        plan.frame = CGRect(x: pad, y: cursorY + 2, width: contentW, height: 62)
        addSubview(plan)
        cursorY += 68

        // Only when there is something to fix. A panel narrowed under its
        // contents leaves components Rack will place outside the module's box,
        // and the width control right above is how you get there.
        if let cv = canvas {
            let strays = cv.document.strayComponents().count
            if strays > 0 {
                let note = NSTextField(wrappingLabelWithString:
                    "⚠ \(strays) component\(strays == 1 ? "" : "s") outside the panel — Rack draws "
                    + "\(strays == 1 ? "it" : "them") beyond the module's edge, unseen and unclickable.")
                note.font = NSFont.systemFont(ofSize: 10)
                note.textColor = ColorSpec.hex("#DD8844").nsColor
                note.maximumNumberOfLines = 3
                note.frame = CGRect(x: pad, y: cursorY, width: contentW, height: 40)
                addSubview(note)
                cursorY += 44
                buttonRow(["Fit to Panel…"], handlers: [
                    { [weak self] in self?.window?.windowController?
                        .tryToPerform(#selector(MainWindowController.pgFitToPanel(_:)), with: nil) },
                ], columns: 1)
            }
        }

        label("SVG units")
        let units = NSPopUpButton(frame: .zero, pullsDown: false)
        units.addItems(withTitles: SVGUnits.allCases.map(\.displayName))
        units.selectItem(at: SVGUnits.allCases.firstIndex(of: document.svgUnits) ?? 0)
        units.font = NSFont.systemFont(ofSize: 11)
        units.toolTip = "Unit for the exported SVG's width/height; the viewBox stays in "
            + "panel pixels either way, so nothing is rescaled. Millimetres is what Rack's "
            + "helper.py and MetaModule rasterisers expect — some reject a unitless size."
        addControl(units, width: 140)
        handlers.append { [weak self] sender in
            guard let self, let p = sender as? NSPopUpButton else { return }
            let i = max(0, min(SVGUnits.allCases.count - 1, p.indexOfSelectedItem))
            let picked = SVGUnits.allCases[i]
            self.canvas?.mutateDocument(name: "SVG Units") { $0.svgUnits = picked }
        }

        label("Text")
        let outlines = makeCheck("Export as outlines", on: document.textAsPaths)
        outlines.toolTip = "VCV Rack's SVG parser (nanosvg) cannot render <text> "
            + "and drops it silently. Leave this on for Rack and MetaModule; turn "
            + "it off only to hand editable text to Illustrator or Inkscape."
        addControl(outlines)
        handlers.append { [weak self] sender in
            guard let self, let b = sender as? NSButton else { return }
            self.canvas?.mutateDocument(name: "Text Export Mode") { $0.textAsPaths = b.state == .on }
        }

        let screws = makeButton("Insert Corner Screws") { [weak self] in
            self?.canvas?.insertCornerScrews()
        }
        screws.frame = CGRect(x: pad, y: cursorY, width: contentW, height: 24)
        addSubview(screws)
        cursorY += 30
    }
}
