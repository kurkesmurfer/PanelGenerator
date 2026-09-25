import AppKit
import PanelKit

/// Right-hand inspector. Rebuilt whenever selection or document identity
/// changes; controls write straight back into the canvas via `mutateSelection`.
final class InspectorView: NSView {

    var canvas: CanvasView?
    var document = PanelDocument()

    override var isFlipped: Bool { true }

    // Layout metrics
    let pad: CGFloat = 14
    let labelW: CGFloat = 86
    let rowH: CGFloat = 22
    let gap: CGFloat = 7
    var cursorY: CGFloat = 12
    /// "sel" or "panel". Lives on the view, not the document: it is how you are
    /// working right now, not a property of the panel. Survives rebuilds.
    var alignTarget: String = "sel"
    /// "gap" (equal edge spacing) or "center" (equal centre-to-centre
    /// spacing, for a selection of mixed-size elements where it's the
    /// *positions* that should divide the span evenly, not the whitespace
    /// between them -- e.g. two switches splitting the run between two
    /// differently-sized knobs into thirds).
    var distributeMode: String = "gap"
    /// "Label Selection…" settings, remembered between runs: labelling a panel
    /// is a dozen passes over different groups of controls, and retyping the
    /// size and gap each time is the tedium the command exists to remove.
    var labelPlacement: LabelPlacement = .below
    var labelGap: CGFloat = 4
    var labelSize: CGFloat = 7
    var labelBold = true
    var labelUppercase = true
    var labelSpaces = true
    var labelColour: ColorSpec? = nil
    var handlers: [(NSControl) -> Void] = []

    var contentW: CGFloat { max(bounds.width - pad * 2 - 14, 120) }

    func rebuild(document doc: PanelDocument, canvas cv: CanvasView) {
        document = doc
        canvas = cv
        handlers = []
        cursorY = 12
        subviews.forEach { $0.removeFromSuperview() }

        buildPanelSection()
        if let p = cv.primaryElement {
            buildElementSection(for: p)
            buildParamsSection(for: p)
            buildComponentSection(for: p)
        } else if let representative = cv.uniformSelection {
            // Several elements of one kind: the same parameter rows, writing to
            // all of them. Mirrored elbows and matched ring sectors are the
            // reason this exists — keeping them identical by hand is the tedium.
            buildSharedSection(for: representative, count: cv.selection.count)
            buildParamsSection(for: representative)
        }
        if !cv.selection.isEmpty {
            buildLayerSection()
        }
        finishLayout()
    }

    private func finishLayout() {
        frame.size = CGSize(width: frame.width, height: cursorY + 16)
    }

    // MARK: Row helpers

    func section(_ title: String) {
        cursorY += 6
        let l = NSTextField(labelWithString: title.uppercased())
        l.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        l.textColor = ColorSpec.hex("#9A9AB0").nsColor
        l.frame = CGRect(x: pad, y: cursorY, width: contentW, height: 15)
        addSubview(l)
        cursorY += 21
    }

    /// A label that marks a value the selection disagrees on. A slider can
    /// only show one number; without the mark it would silently claim that
    /// number is everyone's.
    func plabel<T: Equatable>(_ text: String, _ keyPath: KeyPath<PanelElement, T>) {
        let agrees = canvas?.selectionAgrees(keyPath) ?? true
        label(agrees ? text : text + " ≠")
    }

    @discardableResult
    func label(_ text: String, xOffset: CGFloat = 0) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: 11)
        l.textColor = NSColor.secondaryLabelColor
        l.lineBreakMode = .byTruncatingTail
        l.frame = CGRect(x: pad + xOffset, y: cursorY + 3, width: labelW, height: 16)
        addSubview(l)
        return l
    }

    func addControl(_ v: NSView, width: CGFloat? = nil) {
        let w = width ?? contentW - labelW
        v.frame = CGRect(x: pad + labelW, y: cursorY, width: w, height: rowH)
        v.autoresizingMask = [.minXMargin]
        if let c = v as? NSControl {
            c.tag = handlers.count
            c.target = self
            c.action = #selector(controlAction(_:))
        }
        addSubview(v)
        cursorY += rowH + gap
    }

    /// Two controls sharing a row (e.g. colour well + "none" checkbox).
    func addPair(_ a: NSView, _ b: NSView, split: CGFloat = 0.55) {
        let w = contentW - labelW
        a.frame = CGRect(x: pad + labelW, y: cursorY, width: w * split, height: rowH)
        b.frame = CGRect(x: pad + labelW + w * split + 6, y: cursorY, width: w * (1 - split) - 6, height: rowH)
        for v in [a, b] {
            if let c = v as? NSControl {
                c.tag = handlers.count
                c.target = self
                c.action = #selector(controlAction(_:))
            }
            addSubview(v)
        }
        cursorY += rowH + gap
    }

    @objc func controlAction(_ sender: NSControl) {
        guard handlers.indices.contains(sender.tag) else { return }
        handlers[sender.tag](sender)
    }

    // MARK: Control factories

    func makeField(value: String, placeholder: String = "") -> NSTextField {
        let f = NSTextField(string: value)
        f.placeholderString = placeholder
        f.font = NSFont.systemFont(ofSize: 11)
        f.bezelStyle = .roundedBezel
        return f
    }

    func makeSlider(min minValue: Double, max maxValue: Double, value: Double) -> NSSlider {
        NSSlider(value: value, minValue: minValue, maxValue: maxValue,
                 target: nil, action: nil)
    }

    func makeColorWell(_ color: ColorSpec) -> NSColorWell {
        let cw = NSColorWell(frame: .zero)
        cw.color = color.nsColor
        return cw
    }

    /// A colour well paired with its hex value, kept in sync both ways --
    /// picking a colour updates the hex text, typing a valid hex value
    /// updates the well. Verifying a colour against a known reference
    /// (matching a real product's exact panel background, say) is much
    /// easier reading digits than eyeballing a swatch.
    ///
    /// Deliberately stricter than `ColorSpec.hex(_:)` itself, which falls
    /// back to black on anything malformed -- a typo here should leave the
    /// colour untouched, not blacken it. Invalid input snaps the field back
    /// to the well's own current value instead.
    @discardableResult
    func addColorControl(_ current: ColorSpec, onChange: @escaping (ColorSpec) -> Void) -> NSColorWell {
        let cw = makeColorWell(current)
        let hex = makeField(value: current.hexString)
        hex.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        hex.alignment = .center
        addPair(cw, hex, split: 0.4)
        handlers.append { sender in
            if let c = sender as? NSColorWell {
                let spec = ColorSpec(color: c.color)
                hex.stringValue = spec.hexString
                onChange(spec)
            } else if let f = sender as? NSTextField {
                var t = f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.hasPrefix("#") { t.removeFirst() }
                guard t.count == 6, UInt32(t, radix: 16) != nil else {
                    f.stringValue = ColorSpec(color: cw.color).hexString
                    return
                }
                let spec = ColorSpec.hex(t)
                cw.color = spec.nsColor
                f.stringValue = spec.hexString
                onChange(spec)
            }
        }
        return cw
    }

    func makeCheck(_ title: String, on: Bool) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        b.state = on ? .on : .off
        b.font = NSFont.systemFont(ofSize: 11)
        return b
    }

    func makeButton(_ title: String, handler: @escaping () -> Void) -> NSButton {
        let idx = handlers.count
        handlers.append { _ in handler() }
        let b = NSButton(title: title, target: self, action: #selector(controlAction(_:)))
        b.tag = idx
        b.bezelStyle = .rounded
        b.font = NSFont.systemFont(ofSize: 11)
        b.controlSize = .small
        return b
    }

    /// A rotation close to a "nice" angle -- a multiple of 45° -- snaps to
    /// it. Covers the 90°/45° cases that come up constantly (and 0°, which
    /// is a multiple of 45° too) without fighting a value typed or dragged
    /// to something deliberately in between.
    static func niceAngle(_ v: CGFloat) -> CGFloat {
        let nearest = (v / 45).rounded() * 45
        return abs(v - nearest) < 1.5 ? nearest : v
    }

    func parse(_ sender: NSControl) -> Double? {
        guard let f = sender as? NSTextField else { return nil }
        return Double(f.stringValue.replacingOccurrences(of: ",", with: "."))
    }

    func cgf(_ sender: NSControl) -> CGFloat? { parse(sender).map { CGFloat($0) } }

}

// MARK: - Canvas conveniences used by the inspector

extension CanvasView {
    /// Panel-level edit (name, HP width, format, background). Undoable, and it
    /// keeps the selection. It must NOT go through beginLoad()/endLoad(): that
    /// is the "opened a file from disk" path, and endLoad() calls
    /// edits.removeAllActions() — so every background-colour tick used to wipe
    /// the entire undo stack and deselect.
    func mutateDocument(name: String = "Panel Settings",
                        _ transform: (inout PanelDocument) -> Void) {
        var doc = document
        transform(&doc)
        applyDocument(doc, name: name)
    }

    func insertCornerScrews() {
        var doc = document
        doc.addCornerScrews()
        apply(elements: doc.elements, name: "Corner Screws")
    }
}
