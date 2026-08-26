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
        var loaded: [(url: URL, doc: PanelDocument)] = []
        for document in documents {
            guard let doc = emit(document, to: out) else { allOK = false; continue }
            loaded.append((document, doc))
        }

        // Two documents with one module slug write the same panel SVG and the
        // same header: whichever runs last wins, and nothing about the output
        // says the other existed. Almost always a document saved twice under
        // different names.
        let bySlug = Dictionary(grouping: loaded, by: { $0.doc.moduleSlug })
        for (slug, group) in bySlug.sorted(by: { $0.key < $1.key }) where group.count > 1 {
            let names = group.map { $0.url.lastPathComponent }.sorted().joined(separator: ", ")
            print("  ! \(names) all use the module slug \(slug), so they overwrite each other's "
                  + "res/\(slug).svg and \(CodeGen.moduleIdentifier(group[0].doc))_panel.hpp. "
                  + "Only the last survives.")
            allOK = false
        }

        // One widget library per plugin, not per run. A folder of panels is not
        // a plugin — this one holds several — and writing a single library
        // named after whichever document happened to be first left every other
        // plugin's header including a file that was never written.
        let byPlugin = Dictionary(grouping: loaded, by: { $0.doc.pluginSlug })
        if byPlugin.count > 1 {
            print("  ! These panels belong to \(byPlugin.count) plugins "
                  + "(\(byPlugin.keys.sorted().joined(separator: ", "))). They share one res/ "
                  + "directory here, which no plugin would. Emit each plugin's panels separately.")
        }

        for (slug, group) in byPlugin.sorted(by: { $0.key < $1.key }) {
            guard let first = group.first?.doc else { continue }
            let family = plugin(of: first, near: URL(fileURLWithPath: path),
                                emitted: group.map(\.doc))
            if family.count > group.count {
                print("  · \(slug): widget library covers \(family.count) panels "
                      + "(\(family.count - group.count) not emitted this run)")
            }

            let headers = headerDirectory(out)
            let name = CodeGen.widgetsHeaderName(first)
            do {
                try CodeGen.widgetsHeader(for: family)
                    .write(to: headers.appendingPathComponent(name), atomically: true, encoding: .utf8)
                print("  → \(headers.appendingPathComponent(name).path)")
            } catch {
                print("EMIT FAILED: \(name): \(error)")
                allOK = false
            }

            // The editable seam, written once and then left alone. Overwriting
            // it on every emit would throw away exactly the edits it exists to
            // hold — so an existing one is reported as kept, never touched.
            let baseName = CodeGen.widgetBaseHeaderName(first)
            let baseURL = headers.appendingPathComponent(baseName)
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

    /// Every panel belonging to the same plugin as `doc`: the ones this run
    /// emitted, plus any sibling document that declares the same plugin slug.
    ///
    /// The plugin slug is what makes this safe rather than surprising. A folder
    /// of panels usually holds more than one plugin's work, and a widget
    /// library that swept all of them in would put another plugin's jack in
    /// this one's namespace.
    private static func plugin(of doc: PanelDocument, near source: URL,
                               emitted: [PanelDocument]) -> [PanelDocument] {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory)
        let folder = isDirectory.boolValue ? source : source.deletingLastPathComponent()

        var out = emitted.filter { $0.pluginSlug == doc.pluginSlug }
        let known = Set(out.map(\.moduleSlug))

        let siblings = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil)) ?? []
        for url in siblings.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where url.pathExtension == PanelDocument.fileExtension {
            guard let other = try? PanelDocument.load(from: url),
                  other.pluginSlug == doc.pluginSlug,
                  !known.contains(other.moduleSlug) else { continue }
            out.append(other)
        }
        return out
    }

    /// Where generated headers go.
    ///
    /// A Rack plugin keeps artwork in `res/` at its root and sources in `src/`,
    /// so emitting into a plugin should land each in its own place rather than
    /// piling headers next to plugin.json. When there is no `src/`, the output
    /// directory is a scratch folder and everything stays together.
    static func headerDirectory(_ out: URL) -> URL {
        var isDirectory: ObjCBool = false
        let src = out.appendingPathComponent("src")
        if FileManager.default.fileExists(atPath: src.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return src
        }
        return out
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
                          to: headerDirectory(out)
                              .appendingPathComponent("\(CodeGen.moduleIdentifier(doc))_panel.hpp"))
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
