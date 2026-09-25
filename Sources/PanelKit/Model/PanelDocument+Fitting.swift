import Foundation
import CoreGraphics
import AppKit

// Bringing a panel's contents back inside its edges.

extension PanelDocument {

    // MARK: - Fitting a panel

    /// How to bring a panel's contents back inside its edges.
    package enum FitMode: String, CaseIterable {
        /// Scale every position horizontally about the left margin, sizes
        /// unchanged. Keeps the column structure of a layout exactly — which is
        /// what narrowing a panel usually means — at the cost of closing the
        /// gaps between things.
        case squeeze
        /// Move only what is outside, and only as far as it takes. Nothing that
        /// already fits is disturbed.
        case nudge

        package var displayName: String {
            self == .squeeze ? "Squeeze horizontally (keeps the layout's proportions)"
                             : "Bring strays inside (moves nothing else)"
        }
    }

    /// Components whose centre falls outside the panel.
    ///
    /// Rack places a component exactly where the code says, so one beyond the
    /// module's box is drawn outside it: invisible, unclickable, and still
    /// occupying a parameter.
    package func strayComponents() -> [PanelElement] {
        let panel = CGRect(origin: .zero, size: pixelSize)
        return components.filter {
            let box = widgetBounds(of: $0)
            return !panel.contains(CGPoint(x: box.midX, y: box.midY))
        }
    }

    /// Elements that must move together: a group is one unit, anything
    /// ungrouped is its own.
    ///
    /// This is what keeps a composed widget intact. Scaling each member's
    /// position independently would pull a knob's artwork away from the knob.
    private func movableUnits() -> [[Int]] {
        var byGroup: [UUID: [Int]] = [:]
        var loose: [[Int]] = []
        for (i, el) in elements.enumerated() {
            if let g = el.groupID { byGroup[g, default: []].append(i) } else { loose.append([i]) }
        }
        return loose + byGroup.values
    }

    private func unitBounds(_ unit: [Int]) -> CGRect {
        guard let first = unit.first else { return .zero }
        return unit.dropFirst().reduce(elements[first].frame) { $0.union(elements[$1].frame) }
    }

    /// Bring the panel's contents inside its edges. Returns how many elements moved.
    @discardableResult
    package mutating func fitToPanel(_ mode: FitMode, margin: CGFloat) -> Int {
        let panel = CGRect(origin: .zero, size: pixelSize)
        guard panel.width > margin * 2, panel.height > margin * 2 else { return 0 }
        let inner = panel.insetBy(dx: margin, dy: margin)
        let units = movableUnits()
        var moved = 0

        switch mode {
        case .squeeze:
            // Measured across everything drawn, not just what strays: squeezing
            // the components while the artwork behind them stays put would pull
            // the panel apart.
            var content: CGRect? = nil
            for unit in units {
                let b = unitBounds(unit)
                content = content.map { $0.union(b) } ?? b
            }
            guard let content, content.width > 0 else { return 0 }
            let factor = min(1, inner.width / content.width)
            guard factor < 0.9999 else { return 0 }

            for unit in units {
                let b = unitBounds(unit)
                let target = inner.minX + (b.midX - content.minX) * factor
                let dx = target - b.midX
                guard abs(dx) > 0.001 else { continue }
                for i in unit { elements[i].x += dx }
                moved += unit.count
            }

        case .nudge:
            for unit in units {
                let b = unitBounds(unit)
                // Only what is actually out, and only the distance required.
                var dx: CGFloat = 0, dy: CGFloat = 0
                if b.maxX > inner.maxX { dx = inner.maxX - b.maxX }
                if b.minX + dx < inner.minX { dx = inner.minX - b.minX }
                if b.maxY > inner.maxY { dy = inner.maxY - b.maxY }
                if b.minY + dy < inner.minY { dy = inner.minY - b.minY }
                guard abs(dx) > 0.001 || abs(dy) > 0.001 else { continue }
                for i in unit { elements[i].x += dx; elements[i].y += dy }
                moved += unit.count
            }
        }
        return moved
    }
}
