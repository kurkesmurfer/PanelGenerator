import Foundation

/// Headless export: everything the GUI's two export commands produce, driven
/// from a `.panelgen` on the command line.
///
///     PanelGenerator --emit Panels/Thing.panelgen build/Thing
///
/// This is the join between the editor and a plugin's build. A Makefile can
/// regenerate panel, component artwork and widget code from the document on
/// every build, which is the only way artwork and code stay in step once a
/// panel is revised more than twice.
enum Emit {

    static func run(documentPath: String, outDir rawOut: String) -> Never {
        guard !documentPath.isEmpty else {
            print("usage: PanelGenerator --emit <document.panelgen | directory> [output-dir]")
            fflush(stdout)
            exit(2)
        }

        let path = (documentPath as NSString).expandingTildeInPath
        let out = URL(fileURLWithPath: (rawOut as NSString).expandingTildeInPath)

        // A directory emits every panel in it, so a plugin holding three
        // modules regenerates with one make target rather than three.
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)

        let documents: [URL]
        if isDirectory.boolValue {
            let found = (try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil)) ?? []
            documents = found
                .filter { $0.pathExtension == PanelDocument.fileExtension }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            if documents.isEmpty {
                print("EMIT FAILED: no .\(PanelDocument.fileExtension) documents in \(path)")
                fflush(stdout)
                exit(1)
            }
        } else {
            documents = [URL(fileURLWithPath: path)]
        }

        var allOK = true
        var loaded: [PanelDocument] = []
        for document in documents {
            guard let doc = emit(document, to: out) else { allOK = false; continue }
            loaded.append(doc)
        }

        // One widget library for the whole plugin, written after every panel so
        // it holds all of their widgets. Emitting it per panel meant the last
        // module overwrote the others and took their widgets with it.
        if let first = loaded.first {
            let name = CodeGen.widgetsHeaderName(first)
            do {
                try CodeGen.widgetsHeader(for: loaded)
                    .write(to: out.appendingPathComponent(name), atomically: true, encoding: .utf8)
                print("  → \(out.appendingPathComponent(name).path)")
            } catch {
                print("EMIT FAILED: \(name): \(error)")
                allOK = false
            }

            // The editable seam, written once and then left alone. Overwriting
            // it on every emit would throw away exactly the edits it exists to
            // hold — so an existing one is reported as kept, never touched.
            let baseName = CodeGen.widgetBaseHeaderName(first)
            let baseURL = out.appendingPathComponent(baseName)
            if FileManager.default.fileExists(atPath: baseURL.path) {
                print("  · \(baseURL.path) (kept — yours to edit)")
            } else {
                do {
                    try CodeGen.widgetBaseHeader(first)
                        .write(to: baseURL, atomically: true, encoding: .utf8)
                    print("  → \(baseURL.path) (created once; edit freely)")
                } catch {
                    print("EMIT FAILED: \(baseName): \(error)")
                    allOK = false
                }
            }
        }

        fflush(stdout)
        exit(allOK ? 0 : 1)
    }

    private static func emit(_ docURL: URL, to out: URL) -> PanelDocument? {
        do {
            let doc = try PanelDocument.load(from: docURL)
            let res = out.appendingPathComponent("res")
            try FileManager.default.createDirectory(at: res, withIntermediateDirectories: true)

            var written: [String] = []
            func write(_ text: String, to url: URL) throws {
                try text.write(to: url, atomically: true, encoding: .utf8)
                written.append(url.path)
            }

            // Panel artwork. Named for the module slug because that is the name
            // the generated setPanel() line looks for.
            try write(SVGExporter.documentSVG(doc),
                      to: res.appendingPathComponent("\(doc.moduleSlug).svg"))

            let components = doc.components
            if !components.isEmpty {
                try write(SVGExporter.componentsSVG(doc),
                          to: res.appendingPathComponent("\(doc.moduleSlug)-components.svg"))

                let customs = components.filter {
                    $0.widgetSource == .custom && !$0.customWidgetName.isEmpty
                }
                if !customs.isEmpty {
                    let dir = res.appendingPathComponent("components")
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    var seen = Set<String>()
                    for element in customs where seen.insert(element.customWidgetName).inserted {
                        for file in CodeGen.componentFiles(for: element, in: doc) {
                            try write(SVGExporter.componentSVG(element, in: doc,
                                                               layer: file.layer, units: doc.svgUnits),
                                      to: dir.appendingPathComponent(file.name))
                        }
                    }
                }

                try write(CodeGen.panelHeader(doc),
                          to: out.appendingPathComponent("\(CodeGen.moduleIdentifier(doc))_panel.hpp"))
            }

            print("EMIT OK  \(docURL.lastPathComponent) → \"\(doc.name)\" · "
                  + "\(doc.widthHP)HP \(doc.format.rawValue) · \(doc.elements.count) elements · "
                  + "\(components.count) component\(components.count == 1 ? "" : "s")")
            for path in written { print("  → \(path)") }
            for warning in CodeGen.warnings(doc) { print("  ! \(warning)") }
            // Warnings are advice, not failure: the output is still usable.
            return doc
        } catch {
            print("EMIT FAILED: \(docURL.lastPathComponent): \(error)")
            return nil
        }
    }
}
