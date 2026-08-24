import AppKit

/// Right-hand inspector. Rebuilt whenever selection or document identity
/// changes; controls write straight back into the canvas via `mutateSelection`.
final class InspectorView: NSView {

    private var canvas: CanvasView?
    private var document = PanelDocument()

    override var isFlipped: Bool { true }

    // Layout metrics
    private let pad: CGFloat = 14
    private let labelW: CGFloat = 86
    private let rowH: CGFloat = 22
    private let gap: CGFloat = 7
    private var cursorY: CGFloat = 12
    /// "sel" or "panel". Lives on the view, not the document: it is how you are
    /// working right now, not a property of the panel. Survives rebuilds.
    private var alignTarget: String = "sel"
    private var handlers: [(NSControl) -> Void] = []

    private var contentW: CGFloat { max(bounds.width - pad * 2 - 14, 120) }

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

    private func section(_ title: String) {
        cursorY += 6
        let l = NSTextField(labelWithString: title.uppercased())
        l.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        l.textColor = ColorSpec.hex("#9A9AB0").nsColor
        l.frame = CGRect(x: pad, y: cursorY, width: contentW, height: 15)
        addSubview(l)
        cursorY += 21
    }

    @discardableResult
    private func label(_ text: String, xOffset: CGFloat = 0) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: 11)
        l.textColor = NSColor.secondaryLabelColor
        l.lineBreakMode = .byTruncatingTail
        l.frame = CGRect(x: pad + xOffset, y: cursorY + 3, width: labelW, height: 16)
        addSubview(l)
        return l
    }

    private func addControl(_ v: NSView, width: CGFloat? = nil) {
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
    private func addPair(_ a: NSView, _ b: NSView, split: CGFloat = 0.55) {
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

    @objc private func controlAction(_ sender: NSControl) {
        guard handlers.indices.contains(sender.tag) else { return }
        handlers[sender.tag](sender)
    }

    // MARK: Control factories

    private func makeField(value: String, placeholder: String = "") -> NSTextField {
        let f = NSTextField(string: value)
        f.placeholderString = placeholder
        f.font = NSFont.systemFont(ofSize: 11)
        f.bezelStyle = .roundedBezel
        return f
    }

    private func makeSlider(min minValue: Double, max maxValue: Double, value: Double) -> NSSlider {
        NSSlider(value: value, minValue: minValue, maxValue: maxValue,
                 target: nil, action: nil)
    }

    private func makeColorWell(_ color: ColorSpec) -> NSColorWell {
        let cw = NSColorWell(frame: .zero)
        cw.color = color.nsColor
        return cw
    }

    private func makeCheck(_ title: String, on: Bool) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        b.state = on ? .on : .off
        b.font = NSFont.systemFont(ofSize: 11)
        return b
    }

    private func makeButton(_ title: String, handler: @escaping () -> Void) -> NSButton {
        let idx = handlers.count
        handlers.append { _ in handler() }
        let b = NSButton(title: title, target: self, action: #selector(controlAction(_:)))
        b.tag = idx
        b.bezelStyle = .rounded
        b.font = NSFont.systemFont(ofSize: 11)
        b.controlSize = .small
        return b
    }

    private func parse(_ sender: NSControl) -> Double? {
        guard let f = sender as? NSTextField else { return nil }
        return Double(f.stringValue.replacingOccurrences(of: ",", with: "."))
    }

    private func cgf(_ sender: NSControl) -> CGFloat? { parse(sender).map { CGFloat($0) } }

    // MARK: Sections

    private func buildPanelSection() {
        section("Panel")

        label("Name")
        let name = makeField(value: document.name)
        addControl(name)
        handlers.append { [weak self] sender in
            guard let self, let f = sender as? NSTextField else { return }
            self.canvas?.mutateDocument(name: "Panel Name") { $0.name = f.stringValue.isEmpty ? "Untitled" : f.stringValue }
        }

        label("Width (HP)")
        let hp = makeField(value: String(document.widthHP))
        addControl(hp)
        handlers.append { [weak self] sender in
            guard let self else { return }
            let v = Int(self.parse(sender) ?? 8)
            self.canvas?.mutateDocument(name: "Panel Width") {
                $0.widthHP = min(max(v, PanelMetrics.minPanelWidthHP), PanelMetrics.maxPanelWidthHP)
                sender.stringValue = String($0.widthHP)
            }
        }

        label("Height")
        let pop = NSPopUpButton(frame: .zero, pullsDown: false)
        pop.addItems(withTitles: PanelFormat.allCases.map(\.rawValue))
        pop.selectItem(withTitle: document.format.rawValue)
        pop.font = NSFont.systemFont(ofSize: 11)
        addControl(pop, width: 90)
        handlers.append { [weak self] sender in
            guard let self, let p = sender as? NSPopUpButton,
                  let fmt = PanelFormat(rawValue: p.titleOfSelectedItem ?? "") else { return }
            self.canvas?.mutateDocument(name: "Panel Height") { $0.format = fmt }
        }

        label("Background")
        let bg = makeColorWell(document.background)
        addControl(bg, width: 70)
        handlers.append { [weak self] sender in
            guard let self, let cw = sender as? NSColorWell else { return }
            self.canvas?.mutateDocument(name: "Background") { $0.background = ColorSpec(color: cw.color) }
        }

        label("Plugin slug")
        let pslug = makeField(value: document.pluginSlug, placeholder: "MyPlugin")
        addControl(pslug)
        handlers.append { [weak self] sender in
            guard let self, let f = sender as? NSTextField else { return }
            self.canvas?.mutateDocument(name: "Plugin Slug") { $0.pluginSlug = f.stringValue }
        }

        label("Module slug")
        let mslug = makeField(value: document.moduleSlug, placeholder: "MyModule")
        mslug.toolTip = "Permanent once a patch has been saved with this module — "
            + "changing it later breaks every patch that uses it."
        addControl(mslug)
        handlers.append { [weak self] sender in
            guard let self, let f = sender as? NSTextField else { return }
            self.canvas?.mutateDocument(name: "Module Slug") { $0.moduleSlug = f.stringValue }
        }

        label("Widget ns")
        let wns = makeField(value: document.widgetNamespace, placeholder: "museui")
        wns.toolTip = "Namespace to wrap generated custom widget structs in. "
            + "Leave empty to put them at file scope."
        addControl(wns)
        handlers.append { [weak self] sender in
            guard let self, let f = sender as? NSTextField else { return }
            self.canvas?.mutateDocument(name: "Widget Namespace") { $0.widgetNamespace = f.stringValue }
        }

        label("SVG units")
        let units = NSPopUpButton(frame: .zero, pullsDown: false)
        units.addItems(withTitles: SVGUnits.allCases.map(\.displayName))
        units.selectItem(at: SVGUnits.allCases.firstIndex(of: document.svgUnits) ?? 0)
        units.font = NSFont.systemFont(ofSize: 11)
        units.toolTip = "Unit for the exported SVG's width/height; the viewBox stays in "
            + "panel pixels either way, so nothing is rescaled. Millimetres is what Rack's "
            + "helper.py and MetaModule rasterisers expect — some reject a unitless size."
        addControl(units, width: 140)
        handlers.append { [weak self] sender in
            guard let self, let p = sender as? NSPopUpButton else { return }
            let i = max(0, min(SVGUnits.allCases.count - 1, p.indexOfSelectedItem))
            let picked = SVGUnits.allCases[i]
            self.canvas?.mutateDocument(name: "SVG Units") { $0.svgUnits = picked }
        }

        label("Text")
        let outlines = makeCheck("Export as outlines", on: document.textAsPaths)
        outlines.toolTip = "VCV Rack's SVG parser (nanosvg) cannot render <text> "
            + "and drops it silently. Leave this on for Rack and MetaModule; turn "
            + "it off only to hand editable text to Illustrator or Inkscape."
        addControl(outlines)
        handlers.append { [weak self] sender in
            guard let self, let b = sender as? NSButton else { return }
            self.canvas?.mutateDocument(name: "Text Export Mode") { $0.textAsPaths = b.state == .on }
        }

        let screws = makeButton("Insert Corner Screws") { [weak self] in
            self?.canvas?.insertCornerScrews()
        }
        screws.frame = CGRect(x: pad, y: cursorY, width: contentW, height: 24)
        addSubview(screws)
        cursorY += 30
    }

    private func buildElementSection(for el: PanelElement) {
        section("Element — \(el.kind.displayName)")

        func posSizeFields() {
            let fields: [(String, WritableKeyPath<PanelElement, CGFloat>)] = [
                ("X", \.x), ("Y", \.y), ("W", \.w), ("H", \.h),
            ]
            // Two per row
            for pair in stride(from: 0, to: fields.count, by: 2) {
                let rowViews: [NSView] = []
                _ = rowViews
                var built: [(NSTextField, WritableKeyPath<PanelElement, CGFloat>)] = []
                for j in pair..<min(pair + 2, fields.count) {
                    let (title, kp) = fields[j]
                    label(title, xOffset: j % 2 == 1 ? (contentW - labelW) / 2 : 0)
                    let f = makeField(value: Geo.fmt(el[keyPath: kp]))
                    f.frame = CGRect(x: pad + labelW + (j % 2 == 1 ? (contentW - labelW) / 2 + 4 : 0),
                                     y: cursorY, width: (contentW - labelW) / 2 - 4, height: rowH)
                    f.tag = handlers.count
                    f.target = self
                    f.action = #selector(controlAction(_:))
                    addSubview(f)
                    let weakCanvas = canvas
                    handlers.append { sender in
                        if let v = (sender as? NSTextField)?.stringValue,
                           let d = Double(v.replacingOccurrences(of: ",", with: ".")) {
                            weakCanvas?.mutateSelection("Position/Size") { e in
                                e[keyPath: kp] = CGFloat(d)
                            }
                        }
                    }
                    built.append((f, kp))
                }
                cursorY += rowH + gap
            }
        }
        posSizeFields()

        label("Rotation")
        let rot = makeSlider(min: -180, max: 180, value: Double(el.rotation))
        addControl(rot)
        handlers.append { [weak self] sender in
            guard let self, let s = sender as? NSSlider else { return }
            var v = CGFloat(s.doubleValue)
            if abs(v) < 0.5 { v = 0 }   // the slider can otherwise never quite land on upright
            self.canvas?.mutateSelection("Rotate") { $0.rotation = v }
        }

        label("Fill")
        let fillWell = makeColorWell(el.fill)
        addControl(fillWell, width: 70)
        handlers.append { [weak self] sender in
            guard let self, let cw = sender as? NSColorWell else { return }
            self.canvas?.mutateSelection("Fill") { $0.fill = ColorSpec(color: cw.color) }
        }

        // LCARS swatch bank
        addSwatchBank(current: el.fill)

        label("Stroke")
        let strokeWell = makeColorWell(el.stroke ?? ColorSpec.hex("#FFFFFF"))
        let none = makeCheck("none", on: el.stroke == nil)
        addPair(strokeWell, none)
        let weakCanvas = canvas
        handlers.append { sender in
            if let cw = sender as? NSColorWell {
                weakCanvas?.mutateSelection("Stroke") { $0.stroke = ColorSpec(color: cw.color) }
            } else if let b = sender as? NSButton {
                let noneChecked = b.state == .on
                weakCanvas?.mutateSelection("Stroke") {
                    $0.stroke = noneChecked ? nil : ColorSpec.hex("#FFFFFF")
                }
            }
        }

        label("Width")
        let sw = makeField(value: Geo.fmt(el.strokeWidth))
        addControl(sw)
        handlers.append { [weak self] sender in
            guard let self else { return }
            if let v = self.cgf(sender) {
                self.canvas?.mutateSelection("Stroke Width") { $0.strokeWidth = max(0.25, v) }
            }
        }
    }

    private func addSwatchBank(current: ColorSpec) {
        let swatchesPerRow = 10
        let cell: CGFloat = 17
        let spacing: CGFloat = 3
        for (i, preset) in ColorSpec.lcarsPresets.enumerated() {
            let row = i / swatchesPerRow
            let col = i % swatchesPerRow
            let b = NSButton(frame: CGRect(x: pad + labelW + CGFloat(col) * (cell + spacing),
                                           y: cursorY + CGFloat(row) * (cell + spacing),
                                           width: cell, height: cell))
            b.title = ""
            b.isBordered = false
            b.wantsLayer = true
            b.layer?.backgroundColor = preset.1.nsColor.cgColor
            b.layer?.cornerRadius = 3.5
            b.layer?.borderWidth = current == preset.1 ? 1.6 : 0.6
            b.layer?.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
            b.toolTip = preset.0
            let idx = handlers.count
            let color = preset.1
            let weakCanvas = canvas
            b.target = self
            b.action = #selector(controlAction(_:))
            b.tag = idx
            handlers.append { _ in
                weakCanvas?.mutateSelection("Fill") { $0.fill = color }
            }
        }
        let rows = (ColorSpec.lcarsPresets.count + swatchesPerRow - 1) / swatchesPerRow
        cursorY += CGFloat(rows) * (cell + spacing) + gap
    }

    private func buildParamsSection(for el: PanelElement) {
        switch el.kind.category {
        case .primitive:
            if el.kind == .knobLarge || el.kind == .knobMedium || el.kind == .knobSmall {
                section("Knob")
                label("Pointer °")
                let s = makeSlider(min: 0, max: 360, value: Double(el.params.pointerAngle))
                addControl(s)
                handlers.append { [weak self] sender in
                    guard let self, let sl = sender as? NSSlider else { return }
                    self.canvas?.mutateSelection("Pointer Angle") { $0.params.pointerAngle = CGFloat(sl.doubleValue) }
                }
            }
            if el.kind == .faderVertical || el.kind == .faderHorizontal {
                section("Fader")
                label("Value")
                let s = makeSlider(min: 0, max: 1, value: Double(el.params.value))
                addControl(s)
                handlers.append { [weak self] sender in
                    guard let self, let sl = sender as? NSSlider else { return }
                    self.canvas?.mutateSelection("Fader Value") { $0.params.value = CGFloat(sl.doubleValue) }
                }
            }
            if el.kind == .buttonGroup {
                // Lives here, not under .shape: ElementKind.category sends
                // .buttonGroup to .primitive, so the .shape branch never ran
                // and these controls were unreachable.
                section("Button Group")
                let weakCanvas = canvas

                label("Count")
                let n = makeSlider(min: 2, max: 12, value: Double(el.params.segments))
                n.numberOfTickMarks = 11
                n.allowsTickMarkValuesOnly = true
                addControl(n)
                handlers.append { sender in
                    guard let sl = sender as? NSSlider else { return }
                    weakCanvas?.mutateSelection("Button Count") {
                        $0.params.segments = CGFloat(sl.doubleValue.rounded())
                    }
                }

                label("Layout")
                let lo = NSPopUpButton(frame: .zero, pullsDown: false)
                lo.addItems(withTitles: ["Column", "Row", "Cross (4)", "Circular"])
                lo.selectItem(at: max(0, min(3, Int(el.params.layout))))
                lo.font = NSFont.systemFont(ofSize: 11)
                addControl(lo, width: 110)
                handlers.append { sender in
                    guard let p = sender as? NSPopUpButton else { return }
                    weakCanvas?.mutateSelection("Button Layout") {
                        $0.params.layout = CGFloat(p.indexOfSelectedItem)
                    }
                }
            }
            if el.kind == .led || el.kind == .jack || el.kind == .screw {
                section("Info")
                let note = NSTextField(labelWithString: "Colour comes from the Fill control above.")
                note.font = NSFont.systemFont(ofSize: 10)
                note.textColor = NSColor.secondaryLabelColor
                note.frame = CGRect(x: pad, y: cursorY, width: contentW + labelW, height: 26)
                note.lineBreakMode = .byWordWrapping
                addSubview(note)
                cursorY += 28
            }

        case .shape:
            section("Shape")
            switch el.kind {
            case .box:
                let radii: [(String, WritableKeyPath<ElementParams, CGFloat>)] = [
                    ("Corner TL", \.cornerTL), ("Corner TR", \.cornerTR),
                    ("Corner BR", \.cornerBR), ("Corner BL", \.cornerBL),
                ]
                for (t, kp) in radii {
                    label(t)
                    let s = makeSlider(min: 0, max: Double(max(el.w, el.h) / 2),
                                       value: Double(el.params[keyPath: kp]))
                    addControl(s)
                    let weakCanvas = canvas
                    handlers.append { sender in
                        guard let sl = sender as? NSSlider else { return }
                        weakCanvas?.mutateSelection("Corner Radius") { $0.params[keyPath: kp] = CGFloat(sl.doubleValue) }
                    }
                }
            case .ellipse, .triangle:
                break
            case .elbow:
                let sliders: [(String, WritableKeyPath<ElementParams, CGFloat>, Double)] = [
                    ("Thickness", \.thickness, 40), ("Inner radius", \.innerRadius, 30),
                    ("Arm H", \.armH, 200), ("Arm V", \.armV, 200),
                ]
                for (t, kp, maxV) in sliders {
                    label(t)
                    let s = makeSlider(min: 0, max: maxV, value: Double(el.params[keyPath: kp]))
                    addControl(s)
                    let weakCanvas = canvas
                    handlers.append { sender in
                        guard let sl = sender as? NSSlider else { return }
                        weakCanvas?.mutateSelection("Elbow") { $0.params[keyPath: kp] = CGFloat(sl.doubleValue) }
                    }
                }
                label("")
                let halfW = (contentW - labelW) / 2 - 4
                let fx = makeCheck("Mirror ↔", on: el.params.flipX)
                let fy = makeCheck("Flip ↕", on: el.params.flipY)
                fx.frame = CGRect(x: pad + labelW, y: cursorY, width: halfW, height: rowH)
                fy.frame = CGRect(x: pad + labelW + halfW + 8, y: cursorY, width: halfW, height: rowH)
                addSubview(fx); addSubview(fy)
                let weakCanvas = canvas
                fx.tag = handlers.count
                fx.target = self; fx.action = #selector(controlAction(_:))
                handlers.append { sender in
                    guard let b = sender as? NSButton else { return }
                    weakCanvas?.mutateSelection("Elbow Flip") { $0.params.flipX = b.state == .on }
                }
                fy.tag = handlers.count
                fy.target = self; fy.action = #selector(controlAction(_:))
                handlers.append { sender in
                    guard let b = sender as? NSButton else { return }
                    weakCanvas?.mutateSelection("Elbow Flip") { $0.params.flipY = b.state == .on }
                }
                cursorY += rowH + gap
            case .ringSector:
                label("Start °")
                let s0 = makeSlider(min: -180, max: 180, value: Double(el.params.startAngle))
                addControl(s0)
                let weakCanvas = canvas
                handlers.append { sender in
                    guard let sl = sender as? NSSlider else { return }
                    weakCanvas?.mutateSelection("Ring Start") { $0.params.startAngle = CGFloat(sl.doubleValue) }
                }
                label("Sweep °")
                let s1 = makeSlider(min: -360, max: 360, value: Double(el.params.sweepAngle))
                addControl(s1)
                handlers.append { sender in
                    guard let sl = sender as? NSSlider else { return }
                    weakCanvas?.mutateSelection("Ring Sweep") { $0.params.sweepAngle = CGFloat(sl.doubleValue) }
                }
                label("Thickness")
                let s2 = makeSlider(min: 1, max: Double(max(el.w, el.h) / 2),
                                    value: Double(el.params.thickness))
                addControl(s2)
                handlers.append { sender in
                    guard let sl = sender as? NSSlider else { return }
                    weakCanvas?.mutateSelection("Ring Thickness") { $0.params.thickness = CGFloat(sl.doubleValue) }
                }
            default:
                break
            }

        case .text:
            section("Text")
            label("Content")
            let t = makeField(value: el.params.text)
            addControl(t)
            let weakCanvas = canvas
            handlers.append { sender in
                guard let f = sender as? NSTextField else { return }
                weakCanvas?.mutateSelection("Text") { $0.params.text = f.stringValue }
            }
            label("Size")
            let fs = makeField(value: Geo.fmt(el.params.fontSize))
            addControl(fs)
            handlers.append { [weak self] sender in
                guard let self else { return }
                if let v = self.cgf(sender) {
                    self.canvas?.mutateSelection("Font Size") { $0.params.fontSize = max(4, v) }
                }
            }
            label("")
            let bold = makeCheck("Bold", on: el.params.bold)
            addControl(bold, width: 100)
            let weakCanvas2 = canvas
            handlers.append { sender in
                guard let b = sender as? NSButton else { return }
                weakCanvas2?.mutateSelection("Bold") { $0.params.bold = b.state == .on }
            }
        }
    }

    /// Frame-based button rows — this view is frame-managed; NSStackView's
    /// Auto Layout sizing leaves its arranged buttons invisible here.
    private func buttonRow(_ titles: [String], handlers actions: [() -> Void], columns: Int) {
        let w = (contentW - CGFloat(columns - 1) * 6) / CGFloat(columns)
        for (i, t) in titles.enumerated() {
            let b = makeButton(t, handler: actions[i])
            b.frame = CGRect(x: pad + CGFloat(i) * (w + 6), y: cursorY, width: w, height: 22)
            addSubview(b)
        }
        cursorY += 28
    }


    private func buildComponentSection(for el: PanelElement) {
        section("Component")
        let weakCanvas = canvas

        label("Role")
        let role = NSPopUpButton(frame: .zero, pullsDown: false)
        role.addItems(withTitles: ComponentRole.allCases.map(\.displayName))
        role.selectItem(at: ComponentRole.allCases.firstIndex(of: el.role) ?? 0)
        role.font = NSFont.systemFont(ofSize: 11)
        addControl(role, width: 170)
        handlers.append { sender in
            guard let p = sender as? NSPopUpButton else { return }
            let i = max(0, min(ComponentRole.allCases.count - 1, p.indexOfSelectedItem))
            let picked = ComponentRole.allCases[i]
            weakCanvas?.mutateSelection("Component Role") { $0.role = picked }
        }

        label("Name")
        let nm = makeField(value: el.enumName, placeholder: el.identifierStem)
        addControl(nm)
        handlers.append { sender in
            guard let f = sender as? NSTextField else { return }
            weakCanvas?.mutateSelection("Component Name") { $0.enumName = f.stringValue }
        }

        label("Artwork")
        let src = NSPopUpButton(frame: .zero, pullsDown: false)
        src.addItems(withTitles: WidgetSource.allCases.map(\.displayName))
        src.selectItem(at: WidgetSource.allCases.firstIndex(of: el.widgetSource) ?? 0)
        src.font = NSFont.systemFont(ofSize: 11)
        addControl(src, width: 170)
        handlers.append { sender in
            guard let p = sender as? NSPopUpButton else { return }
            let i = max(0, min(WidgetSource.allCases.count - 1, p.indexOfSelectedItem))
            let picked = WidgetSource.allCases[i]
            weakCanvas?.mutateSelection("Widget Source") { $0.widgetSource = picked }
        }

        label("Rack type")
        let combo = NSComboBox(frame: .zero)
        combo.font = NSFont.systemFont(ofSize: 11)
        combo.addItems(withObjectValues: el.kind.stockWidgetChoices)
        combo.stringValue = el.stockWidget
        combo.completes = true
        addControl(combo)
        handlers.append { sender in
            guard let cb = sender as? NSComboBox else { return }
            weakCanvas?.mutateSelection("Rack Widget") { $0.stockWidget = cb.stringValue }
        }

        label("Custom struct")
        let custom = makeField(value: el.customWidgetName, placeholder: "LcarsKnob")
        addControl(custom)
        handlers.append { sender in
            guard let f = sender as? NSTextField else { return }
            weakCanvas?.mutateSelection("Custom Widget") { $0.customWidgetName = f.stringValue }
        }

        // Millimetres are the unit mm2px() and MetaModule's x_mm both speak, so
        // show them next to the px fields rather than making you convert.
        let mm = el.centerMM
        var note = "Centre \(Geo.fmt(mm.x)) × \(Geo.fmt(mm.y)) mm"
        if el.role.isComponent {
            note += el.widgetSource == .stock
                ? " · size comes from Rack's own artwork; resizing here only moves the guide."
                : " · exported as res/components/\(el.widgetClass).svg at this size."
        } else {
            note += " · artwork, stays in the exported panel."
        }
        let hint = NSTextField(labelWithString: note)
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.textColor = NSColor.secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 3
        hint.frame = CGRect(x: pad, y: cursorY, width: contentW, height: 40)
        addSubview(hint)
        cursorY += 44
    }

    /// One element cannot be aligned to itself, so it always falls back to the
    /// panel however the scope is set.
    private func applyAlign(_ mode: String) {
        guard let cv = canvas else { return }
        cv.alignSelection(mode, to: cv.selection.count > 1 ? alignTarget : "panel")
    }

    private func buildLayerSection() {
        guard let cv = canvas, !cv.selection.isEmpty else { return }

        // One set of align buttons with an explicit scope. Two separate rows
        // labelled identically (L/CX/R/T/M/B for the selection, and again for
        // the panel) meant reaching for "top" and getting the panel's top edge.
        section("Align")
        let multi = cv.selection.count > 1

        label("Relative to")
        let scope = NSPopUpButton(frame: .zero, pullsDown: false)
        scope.addItems(withTitles: ["Selection", "Panel"])
        scope.selectItem(at: (multi && alignTarget == "sel") ? 0 : 1)
        scope.isEnabled = multi
        scope.font = NSFont.systemFont(ofSize: 11)
        scope.toolTip = multi
            ? "Selection: T moves everything to the topmost selected edge, L to the leftmost, and so on. Panel: to the panel's own edges and centre lines."
            : "Only one element is selected, so there is nothing to align it to but the panel."
        addControl(scope, width: 120)
        handlers.append { [weak self] sender in
            guard let self, let p = sender as? NSPopUpButton else { return }
            self.alignTarget = p.indexOfSelectedItem == 1 ? "panel" : "sel"
        }

        // The buttons read alignTarget when clicked, so changing the scope does
        // not have to rebuild the inspector out from under the popup.
        buttonRow(["L", "CX", "R", "T", "M", "B"], handlers: [
            { [weak self] in self?.applyAlign("L") },
            { [weak self] in self?.applyAlign("CX") },
            { [weak self] in self?.applyAlign("R") },
            { [weak self] in self?.applyAlign("T") },
            { [weak self] in self?.applyAlign("CY") },
            { [weak self] in self?.applyAlign("B") },
        ], columns: 6)

        if multi {
            buttonRow(["Dist X", "Dist Y"], handlers: [
                { cv.distributeSelection("X") }, { cv.distributeSelection("Y") },
            ], columns: 2)
        }

        section("Arrange")
        buttonRow(["Front", "Back", "Duplicate", "Delete"], handlers: [
            { [weak self] in self?.canvas?.bringToFront() },
            { [weak self] in self?.canvas?.sendToBack() },
            { [weak self] in self?.canvas?.duplicateSelection() },
            { [weak self] in self?.canvas?.deleteSelection() },
        ], columns: 4)
        buttonRow(["Group", "Ungroup"], handlers: [
            { [weak self] in self?.canvas?.groupSelection() },
            { [weak self] in self?.canvas?.ungroupSelection() },
        ], columns: 2)
        buttonRow(["Copy", "Cut", "Paste"], handlers: [
            { [weak self] in self?.canvas?.copySelection() },
            { [weak self] in self?.canvas?.cutSelection() },
            { [weak self] in self?.canvas?.paste() },
        ], columns: 3)
    }
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
