import AppKit
import UniformTypeIdentifiers
import PanelKit
import PanelCanvas

// Window: SVG, PNG and widget-code export.

extension MainWindowController {

    // MARK: Export

    @objc func pgExportSVG(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.svg]
        panel.nameFieldStringValue = sanitizedFileName + ".svg"
        let componentCount = canvas.document.components.count
        panel.message = componentCount > 0
            ? "Writes the panel artwork plus a \"-components.svg\" positions file for helper.py (\(componentCount) component\(componentCount == 1 ? "" : "s"))."
            : "Nothing is bound as a component yet, so everything exports as artwork."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SVGExporter.documentSVG(canvas.document).write(to: url, atomically: true, encoding: .utf8)
            // Positions go in their own file: everything inside the panel SVG is
            // artwork to Rack, so the marker layer must not ship with it.
            if componentCount > 0 {
                let name = url.deletingPathExtension().lastPathComponent + "-components.svg"
                let sidecar = url.deletingLastPathComponent().appendingPathComponent(name)
                try SVGExporter.componentsSVG(canvas.document).write(to: sidecar, atomically: true, encoding: .utf8)
            }
        } catch {
            showError("Could not export SVG", error)
        }
    }

    @objc func pgExportPNG(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = sanitizedFileName + ".png"
        panel.message = "Exports at 4× resolution (\(Int(canvas.document.pixelSize.width * 4))×\(Int(canvas.document.pixelSize.height * 4)) px)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PNGExporter.pngData(canvas.document, scale: 4).write(to: url)
        } catch {
            showError("Could not export PNG", error)
        }
    }


    @objc func pgExportCode(_ sender: Any?) {
        let doc = canvas.document
        guard !doc.components.isEmpty else {
            let a = NSAlert()
            a.messageText = "Nothing is bound as a component yet."
            a.informativeText = "Give at least one element a Role other than Decoration in the "
                + "inspector. That is what tells PanelGenerator which elements Rack draws itself, "
                + "and those are the ones that turn into widget code."
            a.runModal()
            return
        }

        let customNames = Set(doc.components
            .filter { $0.widgetSource == .custom }
            .map(\.customWidgetName)
            .filter { !$0.isEmpty })

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "hpp") ?? .plainText]
        panel.nameFieldStringValue = CodeGen.moduleIdentifier(doc) + "_panel.hpp"
        panel.message = customNames.isEmpty
            ? "Writes the ID enums and the ModuleWidget constructor body."
            : "Writes the widget code plus a components/ folder with artwork for "
              + "\(customNames.count) custom widget\(customNames.count == 1 ? "" : "s")."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try CodeGen.panelHeader(doc).write(to: url, atomically: true, encoding: .utf8)
            guard !customNames.isEmpty else { return }

            let dir = url.deletingLastPathComponent().appendingPathComponent("components")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var written = Set<String>()
            for el in doc.components where el.widgetSource == .custom {
                let name = el.customWidgetName
                guard !name.isEmpty, written.insert(name).inserted else { continue }
                // A knob needs two files (static body + rotating indicator); a
                // switch needs one per position, of which we can supply the first.
                for file in CodeGen.componentFiles(for: el, in: doc) {
                    try SVGExporter.componentSVG(el, in: doc, layer: file.layer, units: doc.svgUnits)
                        .write(to: dir.appendingPathComponent(file.name),
                               atomically: true, encoding: .utf8)
                }
            }
        } catch {
            showError("Could not export widget code", error)
            return
        }

        presentCodeGenWarnings(CodeGen.warnings(doc), afterExport: true)
    }

    /// `CodeGen.warnings` already catches this document's own name -- two
    /// controls of the same role sharing an identifier -- and already
    /// resolves it (the second becomes NAME_2, and so on) so generated code
    /// always compiles. What it did not have, until now, was any way to
    /// reach the person editing the panel: the check only ever ran from the
    /// `--emit` CLI, printed to a terminal nobody watches while working in
    /// the app. Shown here instead, at the two moments it actually matters:
    /// on demand (File > Check Panel for Issues...) and right after
    /// exporting the widget code a coder agent is about to be handed.
    private func presentCodeGenWarnings(_ warns: [String], afterExport: Bool) {
        guard !warns.isEmpty else {
            guard !afterExport else { return }  // silence on an already-clean export
            let alert = NSAlert()
            alert.messageText = "No issues found"
            alert.informativeText = "Nothing here would trip up code generation."
            alert.runModal()
            return
        }
        let alert = NSAlert()
        alert.messageText = afterExport
            ? "Exported, but \(warns.count) issue\(warns.count == 1 ? "" : "s") found"
            : "\(warns.count) issue\(warns.count == 1 ? "" : "s") found"
        alert.informativeText = warns.map { "• \($0)" }.joined(separator: "\n\n")
        alert.runModal()
    }

    @objc func pgCheckPanel(_ sender: Any?) {
        presentCodeGenWarnings(CodeGen.warnings(canvas.document), afterExport: false)
    }
}
