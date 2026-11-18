import Foundation
import CoreGraphics
import CoreText
import AppKit

/// The module title: a property of the panel, drawn by its design language's
/// rules, so every module in a series has its title at exactly the same height
/// and nobody can drag it out of line.
///
/// - Paperface: Futura Medium capitals, cap height 2.0 mm, cap centre on a
///   line 4.9 mm from the top (measured on the Paris Flash and Tempo di Roma
///   renders).
/// - Kurkesmurfer, and Serge for now: SpaceTime's header lockup — the
///   Kurkesmurfer logo, 5.2 mm tall, a 1.2 mm gap, then the title in Fraunces
///   SemiBold; logo and title centred together on a line 5.8 mm down.
/// - Anything else: a plain centred bold title, centred 5.4 mm down.
package struct TitleStyle {
    package var fontName: String?
    package var fontSize: CGFloat          // panel px
    package var bold: Bool
    package var tracking: CGFloat          // px
    package var uppercase: Bool
    package var centreMM: CGFloat          // cap centre, from the top
    package var mark: (stamp: String, heightMM: CGFloat, gapMM: CGFloat)?
}

extension PanelDocument {

    /// The design language the panel is set to, or the one it is recognised
    /// as (Paperface by its face, grid or cells).
    package var effectiveLanguage: String {
        if let l = designLanguage, !l.isEmpty { return l }
        return PaperfaceGrid.isPaperface(self) ? "paperface" : "generic"
    }

    package var titleStyle: TitleStyle {
        switch effectiveLanguage {
        case "paperface":
            // Font size from the measured cap height and Futura's own ratio.
            let font = FontLibrary.font(named: "Futura-Medium", size: 100, bold: false)
            let capRatio = CTFontGetCapHeight(font as CTFont) / 100
            let size = (2.0 / PanelMetrics.mmPerPixel) / max(capRatio, 0.5)
            return TitleStyle(fontName: "Futura-Medium", fontSize: size, bold: false, tracking: 0.6,
                              uppercase: true, centreMM: 4.9, mark: nil)
        case "kurkesmurfer", "serge":
            // nanoVG size 16 in SpaceTime's addTitle, × CppImport.nanoVGToEm.
            return TitleStyle(fontName: "Fraunces-SemiBold", fontSize: 16 * CppImport.nanoVGToEm, bold: true,
                              tracking: 0.4, uppercase: false, centreMM: 5.8,
                              mark: ("Kurkesmurfer Logo", 5.2, 1.2))
        default:
            return TitleStyle(fontName: nil, fontSize: 12, bold: true, tracking: 0,
                              uppercase: false, centreMM: 5.4, mark: nil)
        }
    }

    /// The title as drawable elements (text, plus the mark's paths for a
    /// lockup), positioned on the panel. Not stored, not selectable: the
    /// Panel inspector's Title field is where it is edited.
    package func titleElements() -> [PanelElement] {
        guard let raw = title?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return [] }
        let style = titleStyle
        let px: (CGFloat) -> CGFloat = { $0 / PanelMetrics.mmPerPixel }

        var text = ElementKind.text.defaultElement(at: .zero)
        text.params.text = style.uppercase ? raw.uppercased() : raw
        text.params.fontName = style.fontName.flatMap { FontLibrary.resolve($0) }
        text.params.fontSize = style.fontSize
        text.params.bold = style.bold
        text.params.tracking = style.tracking == 0 ? nil : style.tracking
        text.fill = .hex("#222322")
        text.followsInk = true
        text.name = "Module Title"
        let size = Renderer.textSize(for: text)
        text.w = size.width; text.h = size.height

        var mark: [PanelElement] = []
        var markW: CGFloat = 0
        if let m = style.mark, let stamp = StampLibrary.stamp(named: m.stamp)?.resolved, !stamp.elements.isEmpty {
            let b = stamp.bounds
            let s = px(m.heightMM) / max(b.height, 0.01)
            markW = b.width * s
            mark = stamp.elements.map { el in
                var e = el
                e.id = UUID()
                e.x = (el.x - b.minX) * s; e.y = (el.y - b.minY) * s
                e.w = el.w * s; e.h = el.h * s
                e.strokeWidth *= s
                if e.kind == .text { e.params.fontSize *= s }
                e.groupID = nil
                return e
            }
        }
        let gap = mark.isEmpty ? 0 : px(style.mark!.gapMM)
        let total = markW + gap + text.w
        let left = (pixelSize.width - total) / 2
        let centreY = px(style.centreMM)
        for i in mark.indices {
            mark[i].x += left
            mark[i].y += centreY - px(style.mark!.heightMM) / 2
        }
        text.x = left + markW + gap
        text.y = centreY - text.h / 2
        return mark + [text]
    }

    /// Turns a title drawn by hand into the panel's title: the first selected
    /// text becomes `title`, and the selected decoration in the title band
    /// (that label, a logo beside it) is removed — the style draws both.
    /// Returns the title taken, or nil if the selection held no text.
    @discardableResult
    package mutating func makeModuleTitle(from ids: Set<UUID>) -> String? {
        let band = 14 / PanelMetrics.mmPerPixel
        let picked = elements.filter { ids.contains($0.id) }
        guard let label = picked.filter({ $0.kind == .text }).min(by: { $0.y < $1.y }) else { return nil }
        title = label.params.text
        let remove = Set(picked.filter { !$0.role.isComponent && $0.frame.maxY <= band }.map(\.id))
        elements.removeAll { remove.contains($0.id) }
        return title
    }

    /// What is drawn: the panel's own elements and the module title.
    package var artwork: [PanelElement] { elements + titleElements() }
}
