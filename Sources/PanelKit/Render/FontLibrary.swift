import Foundation
import AppKit
import CoreText

/// Fonts for text elements: the system font by default, any installed face by
/// PostScript name, and the font files a plugin bundles (`res/fonts/*.ttf`),
/// registered for this process only so nothing has to be installed.
///
/// A document stores the PostScript name, not a path. When that face is not
/// available the label falls back to the system font rather than vanishing.
package enum FontLibrary {

    /// Font files already handled, by path → the PostScript names they hold.
    private static var registered: [String: [String]] = [:]
    private static var searchedNear: Set<String> = []

    /// Registers a font file for this process and returns the PostScript
    /// names of the faces in it. A face that is already available (installed,
    /// or registered from another copy of the file) is not registered twice.
    @discardableResult
    package static func register(_ url: URL) -> [String] {
        let key = url.standardizedFileURL.path
        if let hit = registered[key] { return hit }
        let descriptors = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]) ?? []
        let names = descriptors.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }
        if !names.isEmpty, names.contains(where: { NSFont(name: $0, size: 12) == nil }) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        registered[key] = names
        return names
    }

    /// Registers every font in the `res/fonts` (or `fonts`) folders around a
    /// document: beside it, one level up, and one level into the parent — so
    /// `SpaceTime/Panels/Head.panelgen` finds `SpaceTime/vcv/res/fonts`.
    package static func registerFonts(near document: URL) {
        let fm = FileManager.default
        let dir = document.deletingLastPathComponent()
        let parent = dir.deletingLastPathComponent()
        guard !searchedNear.contains(dir.path) else { return }
        searchedNear.insert(dir.path)

        var bases = [dir, parent]
        let skip: Set<String> = ["build", "dist", "dep", ".git", ".build", "node_modules"]
        let subs = ((try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { !skip.contains($0.lastPathComponent) }
        bases.append(contentsOf: subs)

        for base in bases {
            for rel in ["res/fonts", "fonts"] {
                let folder = base.appendingPathComponent(rel)
                for file in ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                where ["ttf", "otf", "ttc"].contains(file.pathExtension.lowercased()) {
                    register(file)
                }
            }
        }
    }

    /// The face a text element draws with. `name` is a PostScript name; nil
    /// (or one that cannot be found) is the system font, bold or not.
    package static func font(named name: String?, size: CGFloat, bold: Bool) -> NSFont {
        if let name, !name.isEmpty, let f = NSFont(name: name, size: size) { return f }
        return NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
    }

    package static func isAvailable(_ name: String) -> Bool { NSFont(name: name, size: 12) != nil }

    /// Family and style of a PostScript name, for showing it in the inspector.
    package static func familyAndStyle(of name: String) -> (family: String, style: String)? {
        guard let f = NSFont(name: name, size: 12), let family = f.familyName else { return nil }
        let style = members(of: family).first { $0.postScriptName == name }?.style ?? ""
        return (family, style)
    }

    package static func families() -> [String] {
        NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    /// The faces of a family, lightest first as the font manager lists them.
    package static func members(of family: String) -> [(postScriptName: String, style: String)] {
        (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap { m in
            guard m.count >= 2, let ps = m[0] as? String, let style = m[1] as? String else { return nil }
            return (ps, style)
        }
    }

    /// The face a family change should land on: the same style if the family
    /// has it, else a medium/regular/bold one matching the bold flag.
    package static func preferredMember(of family: String, like current: String?, bold: Bool) -> String? {
        let m = members(of: family)
        guard !m.isEmpty else { return nil }
        if let current, let style = familyAndStyle(of: current)?.style,
           let same = m.first(where: { $0.style == style }) { return same.postScriptName }
        let wanted = bold ? ["SemiBold", "Semibold", "Bold", "Medium", "Regular"] : ["Regular", "Medium", "Book", "Roman"]
        for w in wanted { if let hit = m.first(where: { $0.style == w }) { return hit.postScriptName } }
        return m[0].postScriptName
    }
}
