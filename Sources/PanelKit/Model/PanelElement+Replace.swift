import Foundation
import CoreGraphics

// Replacing a control in place: a different kind of element that is still the
// same control as far as the panel, its labels and the generated code know.

extension PanelElement {

    /// This element as a `kind` (with `preset` applied, as a palette drop
    /// would), keeping what makes it this particular control.
    ///
    /// Kept: id (so label bindings and group membership still point at it),
    /// centre, rotation, C++ identifier, custom-widget binding, hidden and
    /// template flags, the layer name unless it was just the old kind's
    /// default, and the role when the new kind is a component too (an output
    /// jack replaced by another jack stays an output). The Rack type is kept
    /// when the new kind offers it.
    ///
    /// From the replacement: size, parameters and appearance, so what lands
    /// looks exactly like what was dropped.
    package func replaced(by kind: ElementKind, preset: String? = nil) -> PanelElement {
        var e = kind.defaultElement(at: .zero)
        if let preset { e.applyPreset(preset) }

        e.id = id
        e.groupID = groupID
        e.isHidden = isHidden
        e.isTemplate = isTemplate
        e.labelOwner = labelOwner
        e.rotation = rotation
        e.rotatesWithValue = rotatesWithValue
        if name != self.kind.displayName { e.name = name }

        e.x = center.x - e.w / 2
        e.y = center.y - e.h / 2

        e.enumName = enumName
        if role.isComponent && e.role.isComponent { e.role = role }
        if widgetSource == .custom {
            e.widgetSource = .custom
            e.customWidgetName = customWidgetName
        }
        if kind.stockWidgetChoices.contains(stockWidget) { e.stockWidget = stockWidget }
        return e
    }
}

extension PanelDocument {

    /// Replaces every element in `ids` in place, keeping document order.
    /// Returns how many were replaced.
    @discardableResult
    package mutating func replace(ids: Set<UUID>, with kind: ElementKind, preset: String? = nil) -> Int {
        var n = 0
        for i in elements.indices where ids.contains(elements[i].id) {
            elements[i] = elements[i].replaced(by: kind, preset: preset)
            n += 1
        }
        return n
    }
}
