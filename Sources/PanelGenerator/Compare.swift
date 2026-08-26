import Foundation
import CoreGraphics

/// Compares the components of two panels, whatever form each one is in.
///
///     PanelGenerator --compare Muse.cpp Panels/Muse.panelgen
///
/// This is the regression check the toolchain needs to be trustworthy. A panel
/// exists in three places at once — the design document, the exported artwork
/// and the module's C++ — and nothing stops them drifting apart. Diffing the
/// files by hand does not work: the same position is written three different
/// ways, and the ordering is not stable between them.
///
/// So the comparison is on meaning, not text. Each side is reduced to a table
/// of identifier, role, widget type and centre in millimetres, matched by
/// identifier, and reported as moved / renamed / missing / added.
enum Compare {

    /// One component, in the only terms the three forms agree on.
    struct Item {
        var identifier: String          // CUTOFF_PARAM — the name Rack uses
        var role: ComponentRole
        var widget: String
        var mm: CGPoint
    }

    struct Side {
        var label: String
        /// The panel a generated file says it came from, if it says.
        var source: String? = nil
        var digest: String? = nil
        var items: [Item] = []
        /// Text by content: labels carry no identifier, so the words are the key.
        var labels: [(text: String, mm: CGPoint)] = []
        var notes: [String] = []
    }

    enum Failure: LocalizedError {
        case unreadable(String)
        case unknownKind(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let p):  return "Could not read \(p)."
            case .unknownKind(let p): return "Don't know how to read \(p) — expected .panelgen, .cpp or .svg."
            }
        }
    }

    // MARK: - Reading a side

    static func side(from rawPath: String) throws -> Side {
        let path = (rawPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent

        switch url.pathExtension.lowercased() {
        case PanelDocument.fileExtension:
            let doc = try PanelDocument.load(from: url)
            // A document stamps itself, so a header can be checked against the
            // panel it claims to come from and not merely against another file.
            var side = Side(label: name, source: doc.name, digest: CodeGen.digest(doc))
            for el in doc.components {
                side.items.append(Item(identifier: el.identifierStem + el.role.enumSuffix,
                                       role: el.role,
                                       widget: el.widgetClass,
                                       mm: doc.componentCentreMM(el)))
            }
            for el in doc.elements where el.kind == .text && el.isHidden != true && el.isTemplate != true {
                side.labels.append((el.params.text, el.centerMM))
            }
            return side

        case "cpp", "cc", "cxx", "hpp", "hh", "h", "mm":
            guard let source = try? String(contentsOf: url, encoding: .utf8) else {
                throw Failure.unreadable(path)
            }
            let siblings = (try? FileManager.default.contentsOfDirectory(
                at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil))?
                .filter { ["h", "hpp", "hh"].contains($0.pathExtension.lowercased()) }
                .prefix(24) ?? []
            let headers = siblings.compactMap { try? String(contentsOf: $0, encoding: .utf8) }

            let outcome = CppImport.outcome(from: source, headers: headers)
            let stamp = provenance(in: source)
            var side = Side(label: name, source: stamp?.source, digest: stamp?.digest,
                            notes: outcome.warnings)
            for el in outcome.elements where el.role.isComponent {
                side.items.append(Item(identifier: el.identifierStem + el.role.enumSuffix,
                                       role: el.role,
                                       widget: el.widgetClass,
                                       mm: el.centerMM))
            }
            for el in outcome.elements where el.kind == .text {
                side.labels.append((el.params.text, el.centerMM))
            }
            return side

        case "svg":
            guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable(path) }
            let outcome = try SVGImport.outcome(from: data)
            var side = Side(label: name, notes: outcome.warnings)
            for el in outcome.elements where el.role.isComponent {
                side.items.append(Item(identifier: el.identifierStem + el.role.enumSuffix,
                                       role: el.role,
                                       widget: el.widgetClass,
                                       mm: el.centerMM))
            }
            return side

        default:
            throw Failure.unknownKind(name)
        }
    }

    // MARK: - The comparison

    struct Difference {
        enum Kind { case moved, role, widget, missing, added, renamed }
        var kind: Kind
        var identifier: String
        var detail: String
    }

    /// `tolerance` is in millimetres. Zero is the wrong default: the three
    /// forms round differently — the C++ carries whatever the author typed, the
    /// document holds panel pixels, the SVG holds two decimals — so an exact
    /// match would report every component as moved. A hundredth of a millimetre
    /// is far below anything a panel can express.
    static func differences(_ a: Side, _ b: Side, tolerance: CGFloat) -> [Difference] {
        var out: [Difference] = []
        var byIdentifierB = Dictionary(grouping: b.items, by: \.identifier)
            .compactMapValues { $0.first }
        let identifiersInA = Set(a.items.map(\.identifier))

        for item in a.items.sorted(by: { $0.identifier < $1.identifier }) {
            guard let other = byIdentifierB.removeValue(forKey: item.identifier) else {
                // Same place, different name: a rename is worth separating from
                // a deletion plus an addition, because it usually is one edit.
                let candidate = byIdentifierB.values.first { other in
                    !identifiersInA.contains(other.identifier)
                        && distance(other.mm, item.mm) <= tolerance
                }
                if let near = candidate {
                    byIdentifierB.removeValue(forKey: near.identifier)
                    out.append(Difference(kind: .renamed, identifier: item.identifier,
                                          detail: "→ \(near.identifier), same position"))
                } else {
                    out.append(Difference(kind: .missing, identifier: item.identifier,
                                          detail: "\(item.widget) at \(format(item.mm))"))
                }
                continue
            }

            let d = distance(item.mm, other.mm)
            if d > tolerance {
                out.append(Difference(kind: .moved, identifier: item.identifier,
                                      detail: "\(format(item.mm)) → \(format(other.mm))  Δ \(mm(d))"))
            }
            if item.role != other.role {
                out.append(Difference(kind: .role, identifier: item.identifier,
                                      detail: "\(item.role.rawValue) → \(other.role.rawValue)"))
            }
            if item.widget != other.widget {
                out.append(Difference(kind: .widget, identifier: item.identifier,
                                      detail: "\(item.widget) → \(other.widget)"))
            }
        }

        for leftover in byIdentifierB.values.sorted(by: { $0.identifier < $1.identifier }) {
            out.append(Difference(kind: .added, identifier: leftover.identifier,
                                  detail: "\(leftover.widget) at \(format(leftover.mm))"))
        }
        return out
    }

    /// Labels have no identifiers, so they are matched by their words. Two
    /// labels reading the same thing are matched nearest-first, which is what
    /// you want on a panel with four jacks all labelled "CV".
    static func labelDifferences(_ a: Side, _ b: Side, tolerance: CGFloat) -> [Difference] {
        var remaining = b.labels
        var out: [Difference] = []

        for label in a.labels {
            let candidates = remaining.enumerated().filter { $0.element.text == label.text }
            guard let best = candidates.min(by: {
                distance($0.element.mm, label.mm) < distance($1.element.mm, label.mm)
            }) else {
                out.append(Difference(kind: .missing, identifier: "\"\(label.text)\"",
                                      detail: "at \(format(label.mm))"))
                continue
            }
            remaining.remove(at: best.offset)
            let d = distance(label.mm, best.element.mm)
            if d > tolerance {
                out.append(Difference(kind: .moved, identifier: "\"\(label.text)\"",
                                      detail: "\(format(label.mm)) → \(format(best.element.mm))  Δ \(mm(d))"))
            }
        }
        for extra in remaining {
            out.append(Difference(kind: .added, identifier: "\"\(extra.text)\"",
                                  detail: "at \(format(extra.mm))"))
        }
        return out
    }

    /// Reads back the stamp `CodeGen.provenance` writes.
    static func provenance(in text: String) -> (source: String, digest: String)? {
        guard let line = text.split(separator: "\n", omittingEmptySubsequences: false)
            .first(where: { $0.contains("PanelGenerator-Source:") }) else { return nil }
        let parts = line.components(separatedBy: "·").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count >= 3,
              let name = parts.first?.components(separatedBy: "PanelGenerator-Source:").last?
                  .trimmingCharacters(in: .whitespaces),
              let digest = parts.last?.components(separatedBy: " ").last else { return nil }
        return (name, digest)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func format(_ p: CGPoint) -> String {
        String(format: "(%.3f, %.3f)", Double(p.x), Double(p.y))
    }

    private static func mm(_ v: CGFloat) -> String {
        String(format: "%.3f mm", Double(v))
    }

    // MARK: - Command line

    static func run(_ pathA: String, _ pathB: String, tolerance: CGFloat, labels: Bool) -> Never {
        do {
            let a = try side(from: pathA)
            let b = try side(from: pathB)

            print("COMPARE")
            print("  A  \(a.label.padding(toLength: max(a.label.count, 28), withPad: " ", startingAt: 0))"
                + "\(a.items.count) components, \(a.labels.count) labels")
            print("  B  \(b.label.padding(toLength: max(b.label.count, 28), withPad: " ", startingAt: 0))"
                + "\(b.items.count) components, \(b.labels.count) labels")
            print("  tolerance \(mm(tolerance))")

            // Said before anything else, because it decides whether the rest of
            // the report is worth reading. Two files from different panels — or
            // one of them stale — disagree in ways that look like a broken
            // panel and are nothing of the kind.
            switch (a.digest, b.digest) {
            case let (x?, y?) where x == y:
                print("  both generated from \(a.source ?? "the same panel") · digest \(x)")
            case let (x?, y?):
                print("")
                print("  ⚠︎  DIFFERENT PANELS. A is \"\(a.source ?? "?")\" (digest \(x)), "
                    + "B is \"\(b.source ?? "?")\" (digest \(y)).")
                print("      Everything below is the difference between two panels, or between one")
                print("      panel and a stale file — not a fault in either. Regenerate both first.")
            default:
                break
            }

            let componentDiffs = differences(a, b, tolerance: tolerance)
            let labelDiffs = labels ? labelDifferences(a, b, tolerance: tolerance) : []

            report("Components", componentDiffs, matched: a.items.count - componentDiffs.filter {
                $0.kind == .missing || $0.kind == .renamed
            }.count)
            if labels {
                report("Labels", labelDiffs, matched: a.labels.count - labelDiffs.filter {
                    $0.kind == .missing
                }.count)
            }

            // Notes from the readers, not differences: a component the C++
            // reader skipped would show up as "missing" above, and knowing it
            // was skipped rather than absent is the difference between a bug in
            // the panel and a gap in the reader.
            for (which, notes) in [(a.label, a.notes), (b.label, b.notes)] where !notes.isEmpty {
                print("\n  Notes from \(which):")
                for note in notes { print("    · \(note)") }
            }

            let total = componentDiffs.count + labelDiffs.count
            print("")
            print(total == 0 ? "COMPARE OK — the two agree." : "COMPARE FAILED — \(total) difference\(total == 1 ? "" : "s").")
            fflush(stdout)
            exit(total == 0 ? 0 : 1)
        } catch {
            print("COMPARE FAILED: \(error.localizedDescription)")
            fflush(stdout)
            exit(2)
        }
    }

    private static func report(_ title: String, _ diffs: [Difference], matched: Int) {
        print("\n  \(title)")
        if diffs.isEmpty {
            print("    \(matched) matched, nothing else to report.")
            return
        }
        print("    \(max(matched, 0)) matched")
        let order: [(Difference.Kind, String)] = [
            (.moved, "moved"), (.role, "role changed"), (.widget, "widget changed"),
            (.renamed, "renamed"), (.missing, "only in A"), (.added, "only in B"),
        ]
        for (kind, heading) in order {
            let group = diffs.filter { $0.kind == kind }
            guard !group.isEmpty else { continue }
            print("    \(group.count) \(heading)")
            for d in group {
                let name = d.identifier.padding(toLength: max(d.identifier.count, 22),
                                                withPad: " ", startingAt: 0)
                print("      \(name) \(d.detail)")
            }
        }
    }
}
