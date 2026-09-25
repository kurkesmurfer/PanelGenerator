import Foundation
import CoreGraphics

/// Saved fragments of a panel, reusable from the palette.
///
/// A brand mark, a wordmark, a row of jacks, an LCARS elbow assembly — the
/// things a house style repeats. Hard-coding any of them would serve exactly
/// one person's panels; saving a selection serves everyone's, and the artwork
/// stays whatever the author drew rather than whatever was approximated here.
///
/// Stamps live outside any document because they belong to the person, not to
/// the panel: `~/Library/Application Support/PanelGenerator/Stamps`.
enum StampLibrary {

    struct Stamp: Identifiable {
        var id: String { name }
        var name: String
        var url: URL
        var elements: [PanelElement]
        /// The palette subsection this stamp belongs in -- the name of the
        /// subfolder it lives under in the library, or nil for the library's
        /// own root ("Stamps" itself). Set by `list()` from where the file
        /// was found; never stored inside the `.pgstamp` file.
        var category: String? = nil

        /// What the stamp occupies, so the palette can preview it and the
        /// canvas can centre it on the drop point.
        var bounds: CGRect {
            guard let first = elements.first else { return .zero }
            return elements.dropFirst().reduce(first.frame) { $0.union($1.frame) }
        }
    }

    static let fileExtension = "pgstamp"

    /// Redirects the library, for the headless self-test — which must not
    /// write into, or read, the person's own palette.
    static var directoryOverride: URL?

    static var directory: URL {
        if let directoryOverride { return directoryOverride }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("PanelGenerator/Stamps", isDirectory: true)
    }

    /// Every stamp in the library: the root ("Stamps" itself, `category ==
    /// nil`) plus one level of subfolders, each subfolder its own palette
    /// section named after itself.
    static func list() -> [Stamp] {
        let dir = directory
        var results = stamps(in: dir, category: nil)
        let subdirs = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for sub in subdirs.sorted(by: { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }) {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: sub.path, isDirectory: &isDir), isDir.boolValue
            else { continue }
            results.append(contentsOf: stamps(in: sub, category: sub.lastPathComponent))
        }
        return results
    }

    /// The `.pgstamp` files directly inside one folder, tagged with the
    /// category that folder represents.
    private static func stamps(in dir: URL, category: String?) -> [Stamp] {
        let found = (try? FileManager.default.contentsOfDirectory(at: dir,
                                                                  includingPropertiesForKeys: nil)) ?? []
        return found
            .filter { $0.pathExtension == fileExtension }
            .sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let elements = try? JSONDecoder().decode([PanelElement].self, from: data),
                      !elements.isEmpty else { return nil }
                return Stamp(name: url.deletingPathExtension().lastPathComponent,
                             url: url, elements: elements, category: category)
            }
    }

    /// Distinct populated category folders, alphabetically -- what the
    /// palette renders as extra sections alongside the general "Stamps" one.
    static func categories() -> [String] {
        Array(Set(list().compactMap { $0.category })).sorted()
    }

    static func stamp(named name: String) -> Stamp? {
        list().first { $0.name == name }
    }

    /// Save a selection. Positions are normalised to the fragment's own origin,
    /// so a stamp drops where you put it rather than where it was drawn.
    @discardableResult
    static func save(_ elements: [PanelElement], as rawName: String) throws -> Stamp {
        let name = fileName(from: rawName)
        guard !elements.isEmpty else { throw Failure.empty }

        var bounds = elements[0].frame
        for el in elements.dropFirst() { bounds = bounds.union(el.frame) }

        // Identity is per document: a stamp carries shapes and sizes, never the
        // ids or the component bindings of the panel it came from. Dropping one
        // must not hand two panels the same component identifier.
        var normalised: [PanelElement] = []
        for element in elements {
            var el = element
            el.id = UUID()
            el.x -= bounds.minX
            el.y -= bounds.minY
            el.groupID = nil
            el.labelOwner = nil
            el.isTemplate = nil
            el.enumName = ""
            normalised.append(el)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name).appendingPathExtension(fileExtension)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(normalised).write(to: url, options: .atomic)
        return Stamp(name: name, url: url, elements: normalised)
    }

    /// A copy ready to insert, with fresh identity and one shared group so the
    /// whole stamp moves as a piece.
    static func instance(of stamp: Stamp, at point: CGPoint) -> [PanelElement] {
        let bounds = stamp.bounds
        let group = stamp.elements.count > 1 ? UUID() : nil
        let origin = CGPoint(x: point.x - bounds.width / 2, y: point.y - bounds.height / 2)
        return stamp.elements.map { element in
            var el = element
            el.id = UUID()
            el.x += origin.x
            el.y += origin.y
            el.groupID = group
            return el
        }
    }

    // MARK: Seeds

    /// Copy the stamps that ship with the app into the person's library, once.
    ///
    /// Never overwrites: a stamp you edited is yours, and a seed that
    /// reappeared over it every launch would be a bug you could not fix from
    /// inside the app. Delete one and it stays deleted for the session; the
    /// marker file below keeps it deleted across launches.
    @discardableResult
    static func installSeeds() -> [String] {
        guard let seeds = seedDirectory() else { return [] }
        let installed = directory.appendingPathComponent(".seeded")
        let already = Set((try? String(contentsOf: installed, encoding: .utf8))?
            .split(separator: "\n").map(String.init) ?? [])
        var seen = already
        var added: [String] = []

        // `keyPrefix` namespaces the ".seeded" marker by category, so a
        // "Round" in one category folder and another in a second never
        // collide, and copies from `srcDir` into `destDir` the same way
        // regardless of whether that is the library root or a subfolder.
        func installFrom(_ srcDir: URL, into destDir: URL, keyPrefix: String) {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: srcDir, includingPropertiesForKeys: nil)) ?? []
            for url in files where url.pathExtension == fileExtension {
                let key = keyPrefix + url.deletingPathExtension().lastPathComponent
                if seen.contains(key) { continue }
                let dest = destDir.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: dest.path) {
                    do { try FileManager.default.copyItem(at: url, to: dest); added.append(key) }
                    catch { continue }
                }
                seen.insert(key)
            }
        }

        installFrom(seeds, into: directory, keyPrefix: "")

        let subdirs = (try? FileManager.default.contentsOfDirectory(
            at: seeds, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for sub in subdirs {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: sub.path, isDirectory: &isDir), isDir.boolValue
            else { continue }
            let category = sub.lastPathComponent
            installFrom(sub, into: directory.appendingPathComponent(category, isDirectory: true),
                        keyPrefix: category + "/")
        }

        if seen != already {
            try? seen.sorted().joined(separator: "\n").write(to: installed, atomically: true, encoding: .utf8)
        }
        return added
    }

    /// Bundle first, then the source tree above the executable — the same order
    /// the manual uses, for the same reason.
    private static func seedDirectory() -> URL? {
        if let inBundle = Bundle.main.resourceURL?.appendingPathComponent("Stamps", isDirectory: true),
           FileManager.default.fileExists(atPath: inBundle.path) {
            return inBundle
        }
        let exe = Bundle.main.executableURL?.resolvingSymlinksInPath()
            ?? URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        var dir = exe.deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("Stamps", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    /// Sanitised so the name is both a filename and something recognisable in
    /// the palette.
    static func fileName(from raw: String) -> String {
        let mapped = raw.map { ch -> Character in
            ch.isLetter || ch.isNumber || ch == "-" || ch == "_" || ch == " " ? ch : "-"
        }
        var out = String(mapped)
        while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: " -_"))
        return out.isEmpty ? "Stamp" : out
    }

    enum Failure: LocalizedError {
        case empty
        var errorDescription: String? { "There is nothing selected to save." }
    }
}
