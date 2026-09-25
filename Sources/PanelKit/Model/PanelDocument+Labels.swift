import Foundation
import CoreGraphics
import AppKit

// Labels, identifiers and names: pairing text with the component it names.

extension PanelDocument {

    /// The label nearest a component, if one is close enough to be about it.
    ///
    /// Distance between centres, not overlap: a label sits beside the control
    /// it names, never on it.
    package func nearestLabel(to el: PanelElement, within limit: CGFloat) -> PanelElement? {
        elements
            .filter { $0.kind == .text && $0.isHidden != true && $0.isTemplate != true }
            .map { ($0, PanelDocument.gap(from: $0.center, to: widgetBounds(of: el))) }
            .filter { $0.1 <= limit }
            .min { $0.1 < $1.1 }?.0
    }

    /// Distance from a point to the nearest edge of a box, zero inside it.
    ///
    /// Measured from the edge, not the centre: a label sits a fixed distance
    /// from the control's rim whatever size the control is, so measuring from
    /// centres puts a big knob's own label out of range while a small one's
    /// stays in. That alone lost every large knob on a real panel.
    package static func gap(from p: CGPoint, to box: CGRect) -> CGFloat {
        let dx = max(box.minX - p.x, 0, p.x - box.maxX)
        let dy = max(box.minY - p.y, 0, p.y - box.maxY)
        return hypot(dx, dy)
    }

    /// A label reduced to what two panels can be expected to agree on.
    /// "LFO 1" and "LFO1" are the same control named twice.
    package static func labelKey(_ text: String) -> String {
        String(text.uppercased().filter { $0.isLetter || $0.isNumber })
    }

    /// A label's text as a C++ identifier stem: "X CV" → X_CV.
    package static func identifier(fromLabel text: String) -> String {
        let mapped = text.uppercased().map { $0.isLetter || $0.isNumber ? $0 : Character("_") }
        var out = String(mapped)
        while out.contains("__") { out = out.replacingOccurrences(of: "__", with: "_") }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if let first = out.first, first.isNumber { out = "_" + out }
        return out
    }

    /// Pair each component with the label nearest it, one label per component,
    /// closest pairs first.
    ///
    /// Greedy by distance rather than per-component nearest: two knobs in a row
    /// would otherwise both claim the label that sits between them, and the one
    /// that actually owns it would be left unnamed.
    package func labelPairs(ids: Set<UUID>, within limit: CGFloat) -> [(component: UUID, label: String)] {
        let targets = elements.filter {
            ids.contains($0.id) && $0.role.isComponent && !isWidgetArtwork($0)
        }
        let labels = elements.filter {
            $0.kind == .text && $0.isHidden != true && $0.isTemplate != true
                && !$0.params.text.trimmingCharacters(in: .whitespaces).isEmpty
        }

        var candidates: [(component: UUID, label: UUID, text: String, distance: CGFloat)] = []
        for target in targets {
            let box = widgetBounds(of: target)
            for label in labels {
                let d = PanelDocument.gap(from: label.center, to: box)
                if d <= limit {
                    candidates.append((target.id, label.id, label.params.text, d))
                }
            }
        }
        candidates.sort { $0.distance < $1.distance }

        var usedComponent = Set<UUID>()
        var usedLabel = Set<UUID>()
        var out: [(component: UUID, label: String)] = []
        for c in candidates where !usedComponent.contains(c.component) && !usedLabel.contains(c.label) {
            usedComponent.insert(c.component)
            usedLabel.insert(c.label)
            out.append((c.component, c.text))
        }
        return out
    }

    /// Turn the labels you drew into identifiers.
    ///
    /// A label and an identifier are different things — one is drawn on the
    /// panel, the other reaches the generated enum — but on a panel that is
    /// already labelled, the label is what you would have typed anyway.
    @discardableResult
    package mutating func nameFromLabels(ids: Set<UUID>, within limit: CGFloat) -> (named: Int, skipped: Int) {
        let pairs = labelPairs(ids: ids, within: limit)
        var named = 0
        for pair in pairs {
            guard let i = elements.firstIndex(where: { $0.id == pair.component }) else { continue }
            let stem = PanelDocument.identifier(fromLabel: pair.label)
            guard !stem.isEmpty else { continue }
            elements[i].enumName = stem
            named += 1
        }
        let total = elements.filter { ids.contains($0.id) && $0.role.isComponent && !isWidgetArtwork($0) }.count
        return (named, total - named)
    }

    /// How a component's identifier was arrived at when adopting.
    package enum AdoptionKind: String {
        /// The two panels say the same thing.
        case exact
        /// The same thing spelled differently — "LFO 1" and "LFO1".
        case normalised
        /// One label is an abbreviation of the other — "ANIM" and "ANIMATE".
        case abbreviated
    }

    package struct Adoption {
        package var label: String
        package var identifier: String
        package var kind: AdoptionKind
    }

    /// Copy identifiers across from another panel, matching on the label beside
    /// each control.
    ///
    /// This is what a redesign needs. A new layout of the same module has the
    /// same controls in different places, so position cannot match them — but
    /// the label under a knob says what the knob is, in both panels, and that
    /// is exactly what the identifier records. Role has to agree too: a panel
    /// can label an input and an output alike, and pairing those would silently
    /// swap two jacks.
    ///
    /// Matching runs in three passes of decreasing confidence, and reports
    /// which pass found each one, because a redesign renames as it goes and a
    /// guess you cannot see is worse than no guess.
    @discardableResult
    package mutating func adoptIdentifiers(from source: PanelDocument, ids: Set<UUID>,
                                   within limit: CGFloat)
    -> (adopted: [Adoption], unmatched: [String]) {
        // Source labels, by role and normalised text. A list rather than one
        // entry: a panel may use one label for two controls — Muse labels both
        // its V/OCT jacks "V OCT" — and collapsing those loses one of them.
        var available: [String: [String]] = [:]
        let sourceIDs = Set(source.elements.map(\.id))
        for pair in source.labelPairs(ids: sourceIDs, within: limit) {
            guard let el = source.elements.first(where: { $0.id == pair.component }),
                  !el.enumName.isEmpty else { continue }
            available["\(el.role.rawValue)|\(PanelDocument.labelKey(pair.label))", default: []]
                .append(el.enumName)
        }

        func take(_ key: String) -> String? {
            guard var list = available[key], !list.isEmpty else { return nil }
            let first = list.removeFirst()
            available[key] = list
            return first
        }

        /// Longest run of leading characters two labels share. "XAMT" and
        /// "XAMOUNT" share "XAM"; "X" and "XCV" share "X", which is why this
        /// needs a floor.
        func commonPrefix(_ a: String, _ b: String) -> Int {
            zip(a, b).prefix { $0.0 == $0.1 }.count
        }

        var adopted: [Adoption] = []
        var unmatched: [String] = []

        // Ordered so that every exact match is taken before any looser one can
        // steal it.
        let mine = labelPairs(ids: ids, within: limit)
        var pending: [(index: Int, role: ComponentRole, label: String, key: String)] = []
        for pair in mine {
            guard let i = elements.firstIndex(where: { $0.id == pair.component }) else { continue }
            pending.append((i, elements[i].role, pair.label,
                            "\(elements[i].role.rawValue)|\(PanelDocument.labelKey(pair.label))"))
        }

        var stillPending: [(index: Int, role: ComponentRole, label: String, key: String)] = []
        for item in pending {
            if let found = take(item.key) {
                elements[item.index].enumName = found
                adopted.append(Adoption(label: item.label, identifier: found, kind: .exact))
            } else {
                stillPending.append(item)
            }
        }

        // What is left is a rename. An abbreviation shares a leading run with
        // its long form, so the best remaining candidate of the same role wins,
        // provided the shared run is long enough to mean something.
        for item in stillPending {
            let key = PanelDocument.labelKey(item.label)
            let floor = max(3, min(key.count, 3))
            var best: (key: String, shared: Int)? = nil
            for (candidateKey, values) in available where !values.isEmpty {
                let parts = candidateKey.components(separatedBy: "|")
                guard parts.count == 2, parts[0] == item.role.rawValue else { continue }
                let shared = commonPrefix(key, parts[1])
                guard shared >= floor else { continue }
                if best == nil || shared > best!.shared { best = (candidateKey, shared) }
            }
            if let best, let found = take(best.key) {
                elements[item.index].enumName = found
                adopted.append(Adoption(label: item.label, identifier: found, kind: .abbreviated))
            } else {
                unmatched.append("\(item.label) (\(item.role.rawValue))")
            }
        }

        return (adopted, unmatched)
    }

    /// Give every selected component a text label carrying its name, in one
    /// action. Returns how many were made and how many selected elements had
    /// nothing to say, so the caller can tell you to name those first rather
    /// than leaving you to count labels.
    ///
    /// Labels are positioned against `widgetBounds`, not the element's own
    /// frame: for a composed widget that is the whole artwork, so a label sits
    /// under the knob rather than under whichever part happens to be the anchor.
    @discardableResult
    package mutating func labelSelection(ids: Set<UUID>,
                                 placement: LabelPlacement,
                                 gap: CGFloat,
                                 fontSize: CGFloat,
                                 bold: Bool,
                                 uppercase: Bool,
                                 spaceUnderscores: Bool,
                                 colour: ColorSpec) -> (created: Int, skipped: Int) {
        // Read the document through a snapshot: the geometry a label is placed
        // against must be the panel as it stands, not as it is part-way through
        // having last run's labels removed from it.
        let doc = self
        let targets = elements
            .filter { ids.contains($0.id) && $0.kind != .text && !doc.isWidgetArtwork($0) }
            .sorted(by: PanelDocument.readingOrder)
        guard !targets.isEmpty else { return (0, 0) }

        // Re-labelling replaces. Without this, changing the size and running
        // again leaves the old labels underneath the new ones.
        let owned = Set(targets.map(\.id))
        elements.removeAll { $0.kind == .text && ($0.labelOwner.map(owned.contains) ?? false) }

        var created = 0
        var skipped = 0
        for target in targets {
            guard let text = doc.labelText(for: target, uppercase: uppercase,
                                       spaceUnderscores: spaceUnderscores) else {
                skipped += 1
                continue
            }
            var label = ElementKind.text.defaultElement(at: .zero)
            label.params.text = text
            label.params.fontSize = max(4, fontSize)
            label.params.bold = bold
            label.fill = colour
            label.name = "Label · \(text)"
            label.labelOwner = target.id
            label.role = .decoration

            let size = Renderer.textSize(for: label)
            label.w = max(size.width, 4)
            label.h = max(size.height, 4)

            let box = doc.widgetBounds(of: target)
            switch placement {
            case .above:
                label.x = box.midX - label.w / 2
                label.y = box.minY - gap - label.h
            case .below:
                label.x = box.midX - label.w / 2
                label.y = box.maxY + gap
            case .left:
                label.x = box.minX - gap - label.w
                label.y = box.midY - label.h / 2
            case .right:
                label.x = box.maxX + gap
                label.y = box.midY - label.h / 2
            }
            elements.append(label)
            created += 1
        }
        return (created, skipped)
    }
}
