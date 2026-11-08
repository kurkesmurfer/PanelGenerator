import Foundation
import CoreGraphics

/// Reading a whole module from its C++: the source, the headers it needs, the
/// sizes of the widgets it places, and the panel artwork it names. The GUI's
/// Import Module Code and the CLI's `--import-module` both go through here, so
/// the two cannot disagree about what a module looks like.
package enum ModuleImport {

    package struct Sources {
        package var url: URL
        package var text: String
        package var headers: [String]
        package var headerURLs: [URL]
        /// The directory holding plugin.json, when one was found.
        package var pluginRoot: URL?
        package var pluginSlug: String?
    }

    package struct Result {
        package var sources: Sources
        package var outcome: CppImport.Outcome
        package var panelURL: URL?
    }

    // MARK: - Sources

    package static func sources(for url: URL) throws -> Sources {
        let text = try String(contentsOf: url, encoding: .utf8)
        let root = pluginRoot(near: url)
        let urls = headerURLs(for: url, text: text, pluginRoot: root)
        return Sources(url: url, text: text,
                       headers: urls.compactMap { try? String(contentsOf: $0, encoding: .utf8) },
                       headerURLs: urls, pluginRoot: root, pluginSlug: root.flatMap(slug(at:)))
    }

    /// Sibling headers — constants routinely live there — plus whatever the
    /// source `#include`s by quoted name, wherever in the plugin it is. A
    /// plugin that keeps its widgets in `widgets/` beside `src/` is otherwise
    /// read without the helpers that place half its panel.
    package static func headerURLs(for url: URL, text: String, pluginRoot: URL?) -> [URL] {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let isHeader: (URL) -> Bool = { ["h", "hpp", "hh"].contains($0.pathExtension.lowercased()) }
        var found: [URL] = []
        var seen = Set<String>()
        func add(_ u: URL) {
            let key = u.standardizedFileURL.path
            guard !seen.contains(key) else { return }
            seen.insert(key)
            found.append(u.standardizedFileURL)
        }
        for u in ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter(isHeader).sorted(by: { $0.path < $1.path }).prefix(24) { add(u) }

        // Where an include may live: beside the file, one up, and one level
        // into the parent (src/../widgets) and into the plugin root.
        var searchDirs = [dir, dir.deletingLastPathComponent()]
        for base in [dir.deletingLastPathComponent(), pluginRoot].compactMap({ $0 }) {
            let subs = ((try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .filter { !["build", "dist", "dep", ".git", "res"].contains($0.lastPathComponent) }
                .sorted { $0.path < $1.path }
            searchDirs.append(contentsOf: subs)
        }
        var queue: [(String, Int)] = [(text, 0)]
        while let (body, depth) = queue.first {
            queue.removeFirst()
            for name in includes(in: body) {
                for d in searchDirs {
                    let candidate = d.appendingPathComponent(name)
                    guard fm.fileExists(atPath: candidate.path) else { continue }
                    let key = candidate.standardizedFileURL.path
                    if !seen.contains(key) {
                        add(candidate)
                        if depth < 2, let t = try? String(contentsOf: candidate, encoding: .utf8) {
                            queue.append((t, depth + 1))
                        }
                    }
                    break
                }
            }
        }
        return found
    }

    static func includes(in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"^\s*#\s*include\s+"([^"]+)""#, options: .anchorsMatchLines)
        else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    /// The directory with plugin.json: beside the source, or up to three
    /// levels above it.
    package static func pluginRoot(near url: URL) -> URL? {
        var dir = url.deletingLastPathComponent()
        for _ in 0..<4 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("plugin.json").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    package static func slug(at root: URL) -> String? {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("plugin.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let slug = json["slug"] as? String, !slug.isEmpty else { return nil }
        return slug
    }

    /// `res/Muse.svg` as written in the source, found on disk.
    package static func resolveResource(_ relative: String, near source: URL, pluginRoot: URL?) -> URL? {
        let dir = source.deletingLastPathComponent()
        let candidates = [dir, dir.deletingLastPathComponent(), pluginRoot].compactMap { $0 }
            .map { $0.appendingPathComponent(relative) }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: - Widget sizes

    /// Rack's own component artwork, when Rack is installed.
    package static func rackComponentLibrary() -> URL? {
        var candidates: [String] = []
        if let rack = ProcessInfo.processInfo.environment["RACK_DIR"] {
            candidates.append(rack + "/res/ComponentLibrary")
        }
        for app in ["VCV Rack 2 Pro", "VCV Rack 2 Free", "VCV Rack 2"] {
            candidates.append("/Applications/\(app).app/Contents/Resources/res/ComponentLibrary")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        candidates.append(home + "/Development/Rack-SDK/res/ComponentLibrary")
        return candidates.map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Rack's light sizes, in mm; lights are drawn, not loaded from SVG.
    static let lightSizes: [(String, CGFloat)] = [
        ("Tiny", 1.088), ("Small", 2.176), ("Medium", 3.176), ("Large", 5.179),
    ]

    /// Sizes in panel pixels for the widgets a module places: Rack's from its
    /// ComponentLibrary SVGs, the plugin's own from the `box.size` its struct
    /// sets or the first SVG it loads.
    package static func widgetSizer(texts: [String], pluginRoot: URL?,
                                    rackLibrary: URL? = rackComponentLibrary()) -> (String, Bool) -> CGSize? {
        var cache: [String: CGSize?] = [:]
        let mm = 75 / 25.4 as CGFloat
        let structs = structBodies(in: texts)

        func svgSize(_ url: URL) -> CGSize? {
            guard let data = try? Data(contentsOf: url) else { return nil }
            return SVGImport.panelSize(from: data)
        }

        func own(_ name: String, depth: Int = 0) -> CGSize? {
            guard depth < 4, let s = structs[name] else { return nil }
            if let v = vector(after: "box.size", in: s.body) {
                return v.mm ? CGSize(width: v.size.width * mm, height: v.size.height * mm) : v.size
            }
            if let root = pluginRoot, let res = firstResourceSVG(in: s.body),
               let size = svgSize(root.appendingPathComponent(res)) {
                return size
            }
            for base in s.bases { if let size = own(base, depth: depth + 1) { return size } }
            return nil
        }

        func stock(_ name: String) -> CGSize? {
            for (prefix, size) in lightSizes where name.hasPrefix(prefix) && name.contains("Light") {
                return CGSize(width: size * mm, height: size * mm)
            }
            guard let lib = rackLibrary else { return nil }
            var bases = [name]
            if name.hasSuffix("Port") { bases.append(String(name.dropLast(4))) }
            if name.contains("Snap") { bases.append(name.replacingOccurrences(of: "Snap", with: "")) }
            for b in bases {
                for file in ["\(b).svg", "\(b)_0.svg", "\(b)_bg.svg"] {
                    if let size = svgSize(lib.appendingPathComponent(file)) { return size }
                }
            }
            return nil
        }

        return { template, custom in
            // `spacetime::Switch4`, `MediumLight<GreenLight>` → the outer type.
            var name = template
            if let lt = name.firstIndex(of: "<") { name = String(name[..<lt]) }
            name = String(name.split(separator: ":").last ?? Substring(name)).trimmingCharacters(in: .whitespaces)
            if let hit = cache[name] { return hit }
            let size = (structs[name] != nil ? own(name) : nil) ?? (custom ? nil : stock(name))
            cache[name] = size
            return size
        }
    }

    struct StructBody { var bases: [String]; var body: String }

    static func structBodies(in texts: [String]) -> [String: StructBody] {
        guard let re = try? NSRegularExpression(pattern: #"\bstruct\s+(\w+)\s*(?::\s*([^{;]*))?\{"#) else { return [:] }
        var out: [String: StructBody] = [:]
        for text in texts {
            let ns = text as NSString
            let u = Array(text.utf16)
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let name = ns.substring(with: m.range(at: 1))
                guard out[name] == nil else { continue }
                var bases: [String] = []
                if m.range(at: 2).location != NSNotFound {
                    bases = ns.substring(with: m.range(at: 2)).split(separator: ",").compactMap {
                        let words = $0.replacingOccurrences(of: "public", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        let t = words.firstIndex(of: "<").map { String(words[..<$0]) } ?? words
                        return t.split(separator: ":").last.map(String.init)
                    }
                }
                var j = m.range.location + m.range.length - 1, depth = 0, end = -1
                while j < u.count {
                    if u[j] == 123 { depth += 1 } else if u[j] == 125 { depth -= 1; if depth == 0 { end = j; break } }
                    j += 1
                }
                guard end > 0 else { continue }
                let start = m.range.location + m.range.length
                out[name] = StructBody(bases: bases, body: ns.substring(with: NSRange(location: start, length: end - start)))
            }
        }
        return out
    }

    /// `box.size = mm2px(Vec(5.f, 6.f))` or `box.size = Vec(30, 30)`.
    static func vector(after lhs: String, in body: String) -> (size: CGSize, mm: Bool)? {
        let esc = NSRegularExpression.escapedPattern(for: lhs)
        let pattern = esc + #"\s*=\s*(mm2px\s*\()?\s*(?:rack::)?(?:math::)?Vec\s*\(([^()]*)\)"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: body, range: NSRange(location: 0, length: (body as NSString).length))
        else { return nil }
        let ns = body as NSString
        let parts = ns.substring(with: m.range(at: 2)).split(separator: ",").map(String.init)
        guard parts.count == 2,
              let w = Expression.evaluate(parts[0], constants: CppImport.builtinConstants),
              let h = Expression.evaluate(parts[1], constants: CppImport.builtinConstants) else { return nil }
        return (CGSize(width: w, height: h), m.range(at: 1).location != NSNotFound)
    }

    static func firstResourceSVG(in body: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: #""(res/[^"]+\.svg)""#),
              let m = re.firstMatch(in: body, range: NSRange(location: 0, length: (body as NSString).length))
        else { return nil }
        return (body as NSString).substring(with: m.range(at: 1))
    }

    // MARK: - Fonts

    /// A font function's face: `fontTitle()` whose body loads
    /// `res/fonts/Fraunces-SemiBold.ttf` → that file, registered for this
    /// process, → its PostScript name.
    package static func fontResolver(texts: [String], pluginRoot: URL?) -> (String) -> String? {
        var cache: [String: String?] = [:]
        return { fn in
            if let hit = cache[fn] { return hit }
            var result: String?
            if let root = pluginRoot, let file = fontFile(of: fn, in: texts) {
                let url = root.appendingPathComponent(file)
                if FileManager.default.fileExists(atPath: url.path) {
                    result = FontLibrary.register(url).first
                }
            }
            cache[fn] = result
            return result
        }
    }

    static func fontFile(of fn: String, in texts: [String]) -> String? {
        guard let head = try? NSRegularExpression(pattern: #"\b"# + NSRegularExpression.escapedPattern(for: fn) + #"\s*\(\s*\)\s*\{"#),
              let file = try? NSRegularExpression(pattern: #""([^"]+\.(?:ttf|otf|ttc))""#) else { return nil }
        for text in texts {
            let ns = text as NSString
            guard let m = head.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { continue }
            let start = m.range.location + m.range.length
            let close = ns.range(of: "}", range: NSRange(location: start, length: ns.length - start))
            let end = close.location == NSNotFound ? ns.length : close.location
            let window = NSRange(location: start, length: end - start)
            if let f = file.firstMatch(in: text, range: window) { return ns.substring(with: f.range(at: 1)) }
        }
        return nil
    }

    // MARK: - Reading

    /// Reads once to learn which panel the widget sets, then again knowing how
    /// big that panel is: Rack's module template positions its screws from
    /// box.size.x, and a module widget's box is whatever setPanel gave it.
    package static func read(_ url: URL) throws -> Result {
        let src = try sources(for: url)
        let sizer = widgetSizer(texts: src.headers + [src.text], pluginRoot: src.pluginRoot)
        let faces = fontResolver(texts: src.headers + [src.text], pluginRoot: src.pluginRoot)
        let first = CppImport.outcome(from: src.text, headers: src.headers, widgetSize: sizer, fontName: faces)
        let panelURL = first.panelResource.flatMap { resolveResource($0, near: url, pluginRoot: src.pluginRoot) }
        let panelSize = panelURL.flatMap { try? Data(contentsOf: $0) }.flatMap { SVGImport.panelSize(from: $0) }
        let outcome = panelSize == nil ? first
            : CppImport.outcome(from: src.text, headers: src.headers, panelSize: panelSize,
                                widgetSize: sizer, fontName: faces)
        return Result(sources: src, outcome: outcome, panelURL: panelURL)
    }

    /// Adds what was read to `doc` — artwork first, so the components land on
    /// top — and returns the report lines.
    package static func apply(_ r: Result, includeArtwork: Bool, to doc: inout PanelDocument) -> [String] {
        var report = r.outcome.warnings
        if includeArtwork, let artworkURL = r.panelURL {
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
        if let hp = r.outcome.widthHP { doc.widthHP = hp }
        if let plugin = r.sources.pluginSlug { doc.pluginSlug = plugin }
        if let slug = r.outcome.moduleSlug {
            doc.moduleSlug = slug
            if doc.name.isEmpty || doc.name == "Untitled" { doc.name = slug }
        }
        doc.elements.append(contentsOf: r.outcome.elements)
        return report
    }
}
