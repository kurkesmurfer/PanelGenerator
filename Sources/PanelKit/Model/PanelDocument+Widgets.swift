import Foundation
import CoreGraphics
import AppKit

// Composed widgets: a named group whose anchor carries the role.

extension PanelDocument {

    // MARK: - Composed widgets
    //
    // A widget is a group with a name. One member is the anchor — it carries
    // the role and the struct name, exactly as a single custom component does —
    // and the rest are its artwork. Reusing groups rather than inventing a
    // second kind of container means Group/Ungroup, move, align and the layer
    // list all keep working on a widget without knowing it is one.

    /// Members of the composed widget anchored on `anchor`, in draw order.
    /// A custom component that is not grouped is a widget of one.
    package func widgetMembers(of anchor: PanelElement) -> [PanelElement] {
        // Only a promoted widget unions its group. A group is also just a
        // selection convenience — rows of controls grouped so they move
        // together — and treating those as widgets collapsed every component in
        // a row onto the group's centre. The custom anchor is the marker that
        // says "this group is one control".
        guard anchor.widgetSource == .custom, !anchor.customWidgetName.isEmpty,
              let group = anchor.groupID else { return [anchor] }
        return elements.filter { $0.groupID == group }
    }

    /// The widget's own frame: the union of its members. This is what the
    /// generated code positions by and what the artwork is sized to — not the
    /// anchor's frame, which is just one piece of the drawing.
    package func widgetBounds(of anchor: PanelElement) -> CGRect {
        let members = widgetMembers(of: anchor)
        guard let first = members.first else { return anchor.frame }
        return members.dropFirst().reduce(first.frame) { $0.union($1.frame) }
    }

    /// Centre in millimetres of the thing Rack positions: the widget's bounds
    /// for a composed widget, the element itself otherwise.
    package func componentCentreMM(_ el: PanelElement) -> CGPoint {
        let bounds = widgetBounds(of: el)
        return CGPoint(x: PanelMetrics.mm(bounds.midX), y: PanelMetrics.mm(bounds.midY))
    }

    /// True when this element is artwork belonging to someone else's widget,
    /// and so must not be drawn into the panel or treated as a component.
    package func isWidgetArtwork(_ el: PanelElement) -> Bool {
        guard let group = el.groupID, !el.role.isComponent else { return false }
        return elements.contains {
            $0.groupID == group && $0.role.isComponent && $0.widgetSource == .custom
        }
    }

    /// Promote a selection to a composed widget: one group, one anchor holding
    /// the name and role, the rest its artwork. The anchor is the member
    /// nearest the centre of the whole, which for a knob is the piece you would
    /// expect the control to be positioned by.
    @discardableResult
    package mutating func makeWidget(ids: Set<UUID>, name: String, role: ComponentRole) -> Bool {
        let members = elements.filter { ids.contains($0.id) }
        guard members.count >= 1, !name.isEmpty else { return false }

        var bounds = members[0].frame
        for m in members.dropFirst() { bounds = bounds.union(m.frame) }
        let middle = CGPoint(x: bounds.midX, y: bounds.midY)
        let anchorID = members.min {
            hypot($0.center.x - middle.x, $0.center.y - middle.y)
                < hypot($1.center.x - middle.x, $1.center.y - middle.y)
        }?.id

        let group = members.compactMap(\.groupID).first ?? UUID()
        for i in elements.indices where ids.contains(elements[i].id) {
            elements[i].groupID = group
            if elements[i].id == anchorID {
                elements[i].role = role
                elements[i].widgetSource = .custom
                elements[i].customWidgetName = name
                if elements[i].enumName.isEmpty { elements[i].enumName = name }
            } else {
                // Artwork, not a component in its own right.
                elements[i].role = .decoration
                elements[i].widgetSource = .stock
                elements[i].customWidgetName = ""
            }
        }
        return true
    }
}
