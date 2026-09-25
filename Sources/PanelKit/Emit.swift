import Foundation

/// Headless export: everything the GUI's two export commands produce, driven
/// from a `.panelgen` on the command line.
///
///     PanelGenerator --emit Panels/Thing.panelgen build/Thing
///     PanelGenerator --emit Panels/Thing.panelgen build/Thing --theme both
///
/// This is the join between the editor and a plugin's build. A Makefile can
/// regenerate panel, component artwork and widget code from the document on
/// every build, which is the only way artwork and code stay in step once a
/// panel is revised more than twice.
package enum Emit {

    /// Which of a themed document's colour variants `--emit` actually writes.
    /// `.auto` (the default -- no `--theme` flag) always writes the dark
    /// variant at its existing name (`<slug>.svg`, byte-identical to every
    /// panel emitted before theming existed) and, only when the document
    /// itself declares a light variant (`PanelDocument.isThemed`), also
    /// writes it alongside as `<slug>-light.svg` -- so a plugin with no
    /// themed panels sees no change at all, and one with a themed panel gets
    /// both files without needing to ask. The explicit values exist because
    /// Goose asked for a way to say exactly which variant(s) a given build
    /// step wants, rather than relying on what a document happens to declare.
    package enum ThemeSelection: String {
        case auto, dark, light, both

        package static func parse(_ s: String) -> ThemeSelection? { ThemeSelection(rawValue: s) }

        /// Which variants to actually write for a given document.
        package func variants(for doc: PanelDocument) -> [ThemeVariant] {
            switch self {
            case .auto:  return doc.isThemed ? [.dark, .light] : [.dark]
            case .dark:  return [.dark]
            case .light: return [.light]
            case .both:  return [.dark, .light]
            }
        }
    }

    package static func run(documentPath: String, outDir rawOut: String, theme: ThemeSelection = .auto) -> Never {
        guard !documentPath.isEmpty else {
            print("usage: PanelGenerator --emit <document.panelgen | directory> [output-dir] [--theme dark|light|both]")
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
            guard let doc = emit(document, to: out, theme: theme) else { allOK = false; continue }
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
    package static func headerDirectory(_ out: URL) -> URL {
        var isDirectory: ObjCBool = false
        let src = out.appendingPathComponent("src")
        if FileManager.default.fileExists(atPath: src.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return src
        }
        return out
    }

    /// `<slug>.svg` for the dark variant (unchanged name, so nothing that
    /// already references it needs to change), `<slug>-light.svg` for the
    /// light one -- matching the convention Peet had already settled on by
    /// hand for GTS (`GTS.svg` / `GTS-light.svg`) before this existed.
    private static func svgName(_ slug: String, variant: ThemeVariant) -> String {
        variant == .dark ? "\(slug).svg" : "\(slug)-light.svg"
    }

    private static func emit(_ docURL: URL, to out: URL, theme: ThemeSelection) -> PanelDocument? {
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
            // the generated setPanel() line looks for. One file per requested
            // theme variant -- just the dark one for an untethemed document
            // under the default `.auto` selection, exactly as before theming
            // existed.
            let variants = theme.variants(for: doc)
            for variant in variants {
                try write(SVGExporter.documentSVG(doc, variant: variant),
                          to: res.appendingPathComponent(svgName(doc.moduleSlug, variant: variant)))
            }

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
                  + "\(components.count) component\(components.count == 1 ? "" : "s")"
                  + (doc.isThemed ? " · themed (\(variants.map(\.rawValue).joined(separator: ", ")))" : ""))
            for path in written { print("  → \(path)") }
            if !doc.isThemed && variants.contains(.light) {
                print("  · --theme \(theme.rawValue) asked for a light variant, but this document has no "
                      + "light background set (View ▸ Theme) -- its light SVG was written anyway, "
                      + "identical to the dark one.")
            }
            for warning in CodeGen.warnings(doc) { print("  ! \(warning)") }
            // Warnings are advice, not failure: the output is still usable.
            return doc
        } catch {
            print("EMIT FAILED: \(docURL.lastPathComponent): \(error)")
            return nil
        }
    }
}
