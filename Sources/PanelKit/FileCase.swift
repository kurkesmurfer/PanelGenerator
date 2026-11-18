import Foundation

/// Writing `OscPlus.svg` over `Oscplus.svg` on a case-insensitive volume (the
/// macOS default) replaces the contents and keeps the old spelling: the atomic
/// rename lands on the existing directory entry. A slug whose capitalisation
/// changed would then never reach the file names — harmless on a Mac, a
/// missing panel on Linux and in git. So before writing, an entry that differs
/// from the wanted name only in case is removed, and the new one is created
/// with the spelling asked for.
package enum FileCase {
    package static func prepare(_ url: URL) {
        let dir = url.deletingLastPathComponent()
        let want = url.lastPathComponent
        let caseSensitive = (try? dir.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey]))?
            .volumeSupportsCaseSensitiveNames ?? true
        guard !caseSensitive,
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path),
              let old = names.first(where: { $0 != want && $0.caseInsensitiveCompare(want) == .orderedSame })
        else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(old))
    }
}
