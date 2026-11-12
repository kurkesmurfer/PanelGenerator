import Foundation
import CoreGraphics

/// Where labels sit relative to the control they belong to — always measured
/// from the control's centre, so labels under a jack and under a knob end up
/// on one line whatever the controls' sizes.
///
/// Defaults are measured on the Paperface 50 renders: SYNC under its jack and
/// FREQ under its knob both sit 7.1 mm below the control's centre; a second
/// line (WAVE / SHAPE) is 2.8 mm further.
package struct LabelGridSpec: Codable, Hashable {
    /// Label centre above/below the control's centre, mm.
    package var offsetMM: CGFloat?
    /// Extra distance per further line, mm.
    package var lineMM: CGFloat?
    /// Label's near edge left/right of the control's centre, mm.
    package var sideMM: CGFloat?

    package init(offsetMM: CGFloat? = nil, lineMM: CGFloat? = nil, sideMM: CGFloat? = nil) {
        self.offsetMM = offsetMM; self.lineMM = lineMM; self.sideMM = sideMM
    }

    package static let defaultOffsetMM: CGFloat = 7.1
    package static let defaultLineMM: CGFloat = 2.8
    package static let defaultSideMM: CGFloat = 5.5
}

extension PanelDocument {

    private var labelMetrics: (offset: CGFloat, line: CGFloat, side: CGFloat) {
        let px: (CGFloat) -> CGFloat = { $0 / PanelMetrics.mmPerPixel }
        return (px(labelGrid?.offsetMM ?? LabelGridSpec.defaultOffsetMM),
                px(labelGrid?.lineMM ?? LabelGridSpec.defaultLineMM),
                px(labelGrid?.sideMM ?? LabelGridSpec.defaultSideMM))
    }

    package func owner(of label: PanelElement) -> PanelElement? {
        guard let id = label.labelOwner else { return nil }
        return elements.first { $0.id == id }
    }

    /// Candidate centres for `label` around its owner: three lines below,
    /// three above, and level to the left and right (edge-anchored, so the
    /// gap is the same whatever the text's length).
    package func labelSlots(for label: PanelElement, owner: PanelElement) -> [CGPoint] {
        let (offset, line, side) = labelMetrics
        let c = owner.center
        var slots: [CGPoint] = []
        for n in 0..<3 {
            let d = offset + line * CGFloat(n)
            slots.append(CGPoint(x: c.x, y: c.y + d))
            slots.append(CGPoint(x: c.x, y: c.y - d))
        }
        slots.append(CGPoint(x: c.x + side + label.w / 2, y: c.y))
        slots.append(CGPoint(x: c.x - side - label.w / 2, y: c.y))
        return slots
    }

    /// The slot nearest `proposed` (a label centre), if one lies within
    /// `reach` px; nil means "not near a slot — use the normal grid".
    package func snappedLabelCenter(_ label: PanelElement, proposed: CGPoint, reach: CGFloat) -> CGPoint? {
        guard let owner = owner(of: label) else { return nil }
        let best = labelSlots(for: label, owner: owner)
            .min { hypot($0.x - proposed.x, $0.y - proposed.y) < hypot($1.x - proposed.x, $1.y - proposed.y) }
        guard let b = best, hypot(b.x - proposed.x, b.y - proposed.y) <= reach else { return nil }
        return b
    }

    /// Labels that belong to any of `ids` and are not themselves in it:
    /// they travel with their control.
    package func labelsFollowing(_ ids: Set<UUID>) -> Set<UUID> {
        Set(elements.filter { $0.kind == .text && !ids.contains($0.id)
            && ($0.labelOwner.map(ids.contains) ?? false) }.map(\.id))
    }

    /// Attaches each selected label to the nearest control (by centre)
    /// within `maxDistanceMM`, then moves it onto its nearest slot. With
    /// exactly one control in the selection, every selected label goes to
    /// that one. Returns how many were attached.
    @discardableResult
    package mutating func attachLabels(_ ids: Set<UUID>, maxDistanceMM: CGFloat = 14) -> Int {
        let selected = elements.filter { ids.contains($0.id) }
        let labels = selected.filter { $0.kind == .text }
        let chosen = selected.filter { $0.role.isComponent }
        let candidates = chosen.count == 1 ? chosen : elements.filter { $0.role.isComponent }
        let reach = maxDistanceMM / PanelMetrics.mmPerPixel
        var n = 0
        for label in labels {
            let c = label.center
            guard let owner = candidates.min(by: { hypot($0.center.x - c.x, $0.center.y - c.y)
                                                 < hypot($1.center.x - c.x, $1.center.y - c.y) }),
                  chosen.count == 1 || hypot(owner.center.x - c.x, owner.center.y - c.y) <= reach,
                  let i = elements.firstIndex(where: { $0.id == label.id }) else { continue }
            elements[i].labelOwner = owner.id
            n += 1
        }
        snapLabels(Set(labels.map(\.id)))
        return n
    }

    package mutating func detachLabels(_ ids: Set<UUID>) {
        for i in elements.indices where ids.contains(elements[i].id) && elements[i].kind == .text {
            elements[i].labelOwner = nil
        }
    }

    /// Moves each owned label in `ids` onto the slot nearest where it is.
    @discardableResult
    package mutating func snapLabels(_ ids: Set<UUID>) -> Int {
        var n = 0
        for i in elements.indices where ids.contains(elements[i].id) && elements[i].kind == .text {
            let label = elements[i]
            guard let s = snappedLabelCenter(label, proposed: label.center, reach: .greatestFiniteMagnitude) else { continue }
            elements[i].x = s.x - label.w / 2
            elements[i].y = s.y - label.h / 2
            n += 1
        }
        return n
    }
}
