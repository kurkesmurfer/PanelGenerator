import AppKit
import PanelKit

// Inspector: per-kind parameters.

extension InspectorView {

    func buildParamsSection(for el: PanelElement) {
        switch el.kind.category {
        case .primitive:
            if el.kind.isKnob {
                section("Knob")
                let weakCanvas = canvas

                plabel("Pointer °", \.params.pointerAngle)
                let s = makeSlider(min: 0, max: 360, value: Double(el.params.pointerAngle))
                addControl(s)
                handlers.append { sender in
                    guard let sl = sender as? NSSlider else { return }
                    weakCanvas?.mutateSelection("Pointer Angle") { $0.params.pointerAngle = CGFloat(sl.doubleValue) }
                }

                plabel("Indicator", \.params.knobStyle)
                let style = NSPopUpButton(frame: .zero, pullsDown: false)
                style.addItems(withTitles: ["Pointer", "Position ring", "Ring + pointer"])
                style.selectItem(at: max(0, min(2, Int(el.params.knobStyle.rounded()))))
                style.font = NSFont.systemFont(ofSize: 11)
                addControl(style, width: 150)
                handlers.append { sender in
                    guard let p = sender as? NSPopUpButton else { return }
                    let picked = CGFloat(max(0, min(2, p.indexOfSelectedItem)))
                    weakCanvas?.mutateSelection("Knob Indicator") { $0.params.knobStyle = picked }
                }

                plabel("Sweep °", \.params.arcSpan)
                let span = makeSlider(min: 90, max: 350, value: Double(el.params.arcSpan))
                span.toolTip = "Total travel of the open ring. 298.8° is Rack's own ±0.83·π, "
                    + "so a knob drawn at that sweep matches what Rack will render."
                addControl(span)
                handlers.append { sender in
                    guard let sl = sender as? NSSlider else { return }
                    weakCanvas?.mutateSelection("Knob Sweep") { $0.params.arcSpan = CGFloat(sl.doubleValue) }
                }

                plabel("Ring width", \.params.arcWidth)
                let aw = makeSlider(min: 0.04, max: 0.22, value: Double(el.params.arcWidth))
                addControl(aw)
                handlers.append { sender in
                    guard let sl = sender as? NSSlider else { return }
                    weakCanvas?.mutateSelection("Knob Ring") { $0.params.arcWidth = CGFloat(sl.doubleValue) }
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

                let isCross = Int(el.params.layout.rounded()) == 2
                plabel("Count", \.params.segments)
                let n = makeSlider(min: 2, max: 12, value: Double(el.params.segments))
                n.numberOfTickMarks = 11
                n.allowsTickMarkValuesOnly = true
                // Cross is four by definition; the slider would look live and
                // do nothing.
                n.isEnabled = !isCross
                n.toolTip = isCross
                    ? "The cross layout is four positions by definition. For three, use Column, Row or Circular."
                    : "Number of positions, 2 to 12."
                addControl(n)
                handlers.append { sender in
                    guard let sl = sender as? NSSlider else { return }
                    weakCanvas?.mutateSelection("Button Count") {
                        $0.params.segments = CGFloat(sl.doubleValue.rounded())
                    }
                }

                // Which position is shown. It is not decoration: a switch
                // exports one SVG per position, so this is how you see what
                // each frame will look like before Rack swaps between them.
                let count = max(2, isCross ? 4 : Int(el.params.segments.rounded()))
                plabel("Position", \.params.value)
                let pos = makeSlider(min: 0, max: Double(count - 1),
                                     value: (Double(el.params.value) * Double(count - 1)).rounded())
                pos.numberOfTickMarks = count
                pos.allowsTickMarkValuesOnly = true
                pos.toolTip = "The position drawn here and in frame 0…\(count - 1) of the exported switch."
                addControl(pos)
                handlers.append { sender in
                    guard let sl = sender as? NSSlider else { return }
                    let fraction = count > 1 ? CGFloat(sl.doubleValue.rounded()) / CGFloat(count - 1) : 0
                    weakCanvas?.mutateSelection("Switch Position") { $0.params.value = fraction }
                }

                plabel("Layout", \.params.layout)
                let lo = NSPopUpButton(frame: .zero, pullsDown: false)
                lo.addItems(withTitles: ["Column", "Row", "Cross (4)", "Circular"])
                lo.selectItem(at: max(0, min(3, Int(el.params.layout))))
                lo.font = NSFont.systemFont(ofSize: 11)
                addControl(lo, width: 110)
                handlers.append { [weak self] sender in
                    guard let p = sender as? NSPopUpButton else { return }
                    weakCanvas?.mutateSelection("Button Layout") {
                        $0.params.layout = CGFloat(p.indexOfSelectedItem)
                    }
                    self?.scheduleRebuild()   // Count enables or disables with it
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
                    plabel(t, (\PanelElement.params).appending(path: kp))
                    let s = makeSlider(min: 0, max: Double(max(el.w, el.h) / 2),
                                       value: Double(el.params[keyPath: kp]))
                    addControl(s)
                    let weakCanvas = canvas
                    handlers.append { sender in
                        guard let sl = sender as? NSSlider else { return }
                        weakCanvas?.mutateSelection("Corner Radius") { $0.params[keyPath: kp] = CGFloat(sl.doubleValue) }
                    }
                }

                // Notch: a rectangular tab on one edge, for "sculpting" this
                // box's outline around a neighbouring one (Serge's GTO
                // channel brackets) while keeping every corner rounded,
                // including the two new reentrant ones the tab creates.
                let notchEdgeNow = max(0, min(4, Int(el.params.notchEdge.rounded())))
                plabel("Notch Edge", \.params.notchEdge)
                let edgePopup = NSPopUpButton(frame: .zero, pullsDown: false)
                edgePopup.addItems(withTitles: ["None", "Top", "Right", "Bottom", "Left"])
                edgePopup.selectItem(at: notchEdgeNow)
                edgePopup.font = NSFont.systemFont(ofSize: 11)
                addControl(edgePopup, width: 110)
                let weakCanvasEdge = canvas
                handlers.append { [weak self] sender in
                    guard let p = sender as? NSPopUpButton else { return }
                    weakCanvasEdge?.mutateSelection("Notch Edge") {
                        $0.params.notchEdge = CGFloat(p.indexOfSelectedItem)
                    }
                    self?.scheduleRebuild()   // sliders enable/disable with it
                }

                let notchOn = notchEdgeNow != 0
                let alongEdge = (notchEdgeNow == 1 || notchEdgeNow == 3) ? el.w : el.h
                let notchSliders: [(String, WritableKeyPath<ElementParams, CGFloat>, Double)] = [
                    ("Notch Start", \.notchStart, Double(max(alongEdge, 1))),
                    ("Notch Length", \.notchLength, Double(max(alongEdge, 1))),
                    ("Notch Depth", \.notchDepth, Double(max(el.w, el.h))),
                    ("Notch Radius", \.notchRadius, Double(max(el.w, el.h) / 2)),
                ]
                for (t, kp, maxV) in notchSliders {
                    plabel(t, (\PanelElement.params).appending(path: kp))
                    let s = makeSlider(min: 0, max: maxV, value: Double(el.params[keyPath: kp]))
                    s.isEnabled = notchOn
                    addControl(s)
                    let weakCanvas2 = canvas
                    handlers.append { sender in
                        guard let sl = sender as? NSSlider else { return }
                        weakCanvas2?.mutateSelection("Notch") { $0.params[keyPath: kp] = CGFloat(sl.doubleValue) }
                    }
                }

                label("Invert")
                let invert = makeCheck("Cut inward (recess)", on: el.params.notchInvert)
                invert.isEnabled = notchOn
                invert.toolTip = "Off: the notch is a tab that reaches OUT toward a "
                    + "smaller neighbour (Serge's GTO brackets). On: it cuts a recess "
                    + "IN instead, for when the neighbour is the bigger shape and this "
                    + "box needs to make room for it."
                addControl(invert)
                let weakCanvasInvert = canvas
                handlers.append { sender in
                    guard let b = sender as? NSButton else { return }
                    weakCanvasInvert?.mutateSelection("Notch Invert") { $0.params.notchInvert = b.state == .on }
                }
            case .ellipse, .triangle:
                break
            case .line:
                // Bow: sideways offset of the curve's control point from
                // the straight midpoint. 0 is dead straight; Serge's own
                // hardware often bows this kind of connector slightly
                // around whatever sits between a knob and its jack.
                plabel("Bow", \.params.lineBow)
                let maxBow = Double(max(el.w, el.h, 20))
                let s = makeSlider(min: -maxBow, max: maxBow, value: Double(el.params.lineBow))
                s.toolTip = "0 = straight. Positive or negative bows the line sideways -- "
                    + "Serge's own convention for a curved signal-path line tying a knob "
                    + "to the jack it belongs to."
                addControl(s)
                let weakCanvas = canvas
                handlers.append { sender in
                    guard let sl = sender as? NSSlider else { return }
                    weakCanvas?.mutateSelection("Bow") { $0.params.lineBow = CGFloat(sl.doubleValue) }
                }
            case .elbow, .swirl:
                // Arm H and Knee (a swirl's two horizontal-run lengths)
                // both compete for the same fixed frame width -- the whole
                // shape is rescaled to fit its box, so raising one relative
                // to the other is what makes the split lopsided, not the
                // absolute values. A high ceiling here lets that lopsidedness
                // go much further than 200 would allow. Arm V has no such
                // partner (it's the swirl's one shared spine length / the
                // elbow's only vertical run) but gets the same higher
                // ceiling for consistency.
                // Thickness/Thickness V share a ceiling so either arm can
                // be pushed fat without one hitting a lower cap than the
                // other. Inner radius gets the same headroom -- the render
                // already clamps it to min(thickness, thicknessV), so a fat
                // band can still get a properly proportioned round inner
                // corner instead of one that looks pinched next to it.
                var sliders: [(String, WritableKeyPath<ElementParams, CGFloat>, Double)] = [
                    ("Thickness", \.thickness, 200), ("Thickness V", \.thicknessV, 200),
                    ("Inner radius", \.innerRadius, 200),
                    ("Arm H", \.armH, 1000), ("Arm V", \.armV, 1000),
                ]
                if el.kind == .swirl {
                    // The knee is where the spine sits: equal Arm H / Knee
                    // keeps it centred, same as a single shared arm length
                    // would; pulling them apart shifts it off-centre.
                    sliders.append(("Knee (Arm H top)", \.armH2, 1000))
                }
                for (t, kp, maxV) in sliders {
                    plabel(t, (\PanelElement.params).appending(path: kp))
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
            case .symbol:
                let weakCanvas = canvas
                let spec = SymbolCatalogue.spec(el.params.symbol)

                label("Symbol")
                let fill = el.fill
                let choose = NSButton(frame: .zero)
                choose.title = " " + spec.name
                choose.image = SymbolSwatch.image(spec.id, size: CGSize(width: 17, height: 17), color: fill)
                choose.imagePosition = .imageLeading
                choose.bezelStyle = .rounded
                choose.font = NSFont.systemFont(ofSize: 11)
                addControl(choose)
                handlers.append { [weak self] sender in
                    guard let button = sender as? NSButton else { return }
                    SymbolPicker.present(from: button, color: fill, selected: spec.id) { id in
                        weakCanvas?.mutateSelection("Symbol") { $0.applySymbol(id) }
                        // The parameter rows below belong to the old symbol.
                        self?.scheduleRebuild()
                    }
                }

                plabel("Weight", \.params.weight)
                let wt = makeSlider(min: Double(SymbolCatalogue.minWeight),
                                    max: Double(SymbolCatalogue.maxWeight),
                                    value: Double(el.params.weight))
                addControl(wt)
                handlers.append { sender in
                    guard let s = sender as? NSSlider else { return }
                    weakCanvas?.mutateSelection("Symbol Weight") { $0.params.weight = CGFloat(s.doubleValue) }
                }

                let slots: [WritableKeyPath<ElementParams, CGFloat>] =
                    [\.symbolA, \.symbolB, \.symbolC, \.symbolD]
                for (i, title) in spec.parameters.enumerated() {
                    guard let title, i < slots.count else { continue }
                    let kp = slots[i]
                    plabel(title, (\PanelElement.params).appending(path: kp))
                    let s = makeSlider(min: 0, max: 1, value: Double(el.params[keyPath: kp]))
                    addControl(s)
                    handlers.append { sender in
                        guard let sl = sender as? NSSlider else { return }
                        weakCanvas?.mutateSelection("Symbol Parameter") {
                            $0.params[keyPath: kp] = CGFloat(sl.doubleValue)
                        }
                    }
                }

            case .ringSector:
                plabel("Start °", \.params.startAngle)
                let s0 = makeSlider(min: -180, max: 180, value: Double(el.params.startAngle))
                addControl(s0)
                let weakCanvas = canvas
                handlers.append { sender in
                    guard let sl = sender as? NSSlider else { return }
                    weakCanvas?.mutateSelection("Ring Start") { $0.params.startAngle = CGFloat(sl.doubleValue) }
                }
                plabel("Sweep °", \.params.sweepAngle)
                let s1 = makeSlider(min: -360, max: 360, value: Double(el.params.sweepAngle))
                addControl(s1)
                handlers.append { sender in
                    guard let sl = sender as? NSSlider else { return }
                    weakCanvas?.mutateSelection("Ring Sweep") { $0.params.sweepAngle = CGFloat(sl.doubleValue) }
                }
                plabel("Thickness", \.params.thickness)
                let s2 = makeSlider(min: 1, max: Double(max(el.w, el.h) / 2),
                                    value: Double(el.params.thickness))
                addControl(s2)
                handlers.append { sender in
                    guard let sl = sender as? NSSlider else { return }
                    weakCanvas?.mutateSelection("Ring Thickness") { $0.params.thickness = CGFloat(sl.doubleValue) }
                }
            case .path:
                // No parameters by design: an imported bezier does not carry
                // the fact that it was once an elbow. Say so, rather than
                // showing an empty section that looks broken.
                let note = NSTextField(wrappingLabelWithString:
                    "Imported artwork. Move, scale, rotate and recolour it; there is nothing "
                    + "parametric to edit. Redraw it as a shape if you need to change its form.")
                note.font = NSFont.systemFont(ofSize: 10)
                note.textColor = ColorSpec.hex("#9A9AB0").nsColor
                note.frame = CGRect(x: pad, y: cursorY, width: contentW, height: 46)
                addSubview(note)
                cursorY += 50

            default:
                break
            }

        case .text:
            section("Text")
            plabel("Content", \.params.text)
            let t = makeField(value: el.params.text)
            addControl(t)
            let weakCanvas = canvas
            handlers.append { sender in
                guard let f = sender as? NSTextField else { return }
                weakCanvas?.mutateSelection("Text") { $0.params.text = f.stringValue }
            }
            plabel("Size", \.params.fontSize)
            let fs = makeField(value: Geo.fmt(el.params.fontSize))
            fs.toolTip = "\(Geo.fmt(PanelMetrics.mm(el.params.fontSize))) mm. Jack labels are "
                + "2.0–2.5 mm (6–7.5 px), knob labels 2.5–3.0, section headers 3.0–4.0. "
                + "Anything under about 2 mm disappears on MetaModule's 240 px faceplate."

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
}
