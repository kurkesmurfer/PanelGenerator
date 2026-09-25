import AppKit
import CoreGraphics
import PanelKit

// Canvas: mouse gestures and snapping.

extension CanvasView {

    // MARK: Mouse interaction

    enum DragMode {
        case idle
        case moving(origFrames: [UUID: CGRect])
        case resizing(dir: HandleDir, orig: CGRect, rotation: CGFloat, center: CGPoint)
        case rotating(origRotation: CGFloat, center: CGPoint, startAngle: CGFloat)
        case mirroring(axis: MirrorAxis, orig: Bool)
        case groupResizing(orig: CGRect, origFrames: [UUID: CGRect])
        case groupRotating(center: CGPoint, startAngle: CGFloat, origFrames: [UUID: CGRect], origRotations: [UUID: CGFloat])
        case marquee(start: CGPoint, baseSelection: Set<UUID>)
    }

    /// Mirror axis controlled by an overlay handle.
    enum MirrorAxis { case x, y }
    enum OverlayHandle { case rotate, mirrorX, mirrorY }



    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isGestureActive = true
        // Reset here rather than per-branch. The marquee branch below used to
        // omit it, so a click on empty canvas after a resize or a group drag
        // inherited didDrag == true and the deselect on mouseUp never fired.
        didDrag = false
        let p = panelPoint(from: event)

        if event.clickCount == 2, let el = element(at: p), selection == [el.id] {
            // Double-click cycles nothing for now; keep selection.
        }

        // -1. Multi-selection: group resize / rotate handles.
        if selection.count > 1, let b = selectionBounds {
            let corner = activeHandles(for: b).contains { d, r in
                (d == .nw || d == .ne || d == .sw || d == .se) && r.contains(p)
            }
            let rp = CGPoint(x: b.midX, y: b.minY - overlayHandleOffset)
            if corner {
                downPanelPoint = p; didDrag = false
                dragMode = .groupResizing(orig: b, origFrames: frameMap())
                beginGestureUndo("Group Resize")
                return
            }
            if badgeRect(at: rp).contains(p) {
                downPanelPoint = p; didDrag = false
                dragMode = .groupRotating(center: CGPoint(x: b.midX, y: b.midY),
                                          startAngle: atan2(p.y - b.midY, p.x - b.midX),
                                          origFrames: frameMap(), origRotations: rotationMap())
                beginGestureUndo("Group Rotate")
                return
            }
        }

        // 0. Rotation / mirror handles (single selection).
        if let h = overlayHandle(at: p), let prim = primaryElement {
            switch h {
            case .rotate:
                dragMode = .rotating(origRotation: prim.rotation, center: prim.center,
                                     startAngle: atan2(p.y - prim.center.y, p.x - prim.center.x))
                beginGestureUndo("Rotate")
            case .mirrorX:
                dragMode = .mirroring(axis: .x, orig: prim.params.flipX)
            case .mirrorY:
                dragMode = .mirroring(axis: .y, orig: prim.params.flipY)
            }
            downPanelPoint = p
            didDrag = false
            return
        }

        // 1. Handles first (single selection; rotated elements resize along
        //    their own tilted axes -- see `toLocal`).
        if let dir = handle(at: p), let prim = primaryElement {
            downPanelPoint = p   // must anchor THIS click — stale anchor made resizes explode
            dragMode = .resizing(dir: dir, orig: prim.frame, rotation: prim.rotation, center: prim.center)
            beginGestureUndo("Resize")
            didDrag = false
            return
        }

        // 2. Hit test elements (topmost first). Groups are selected and moved
        //    as a unit: a click on any member expands to the whole group HERE,
        //    so the drag that follows carries every member with it. (Expanding
        //    only at mouseUp let a click-drag move a lone member out of its
        //    group, silently splitting it.)
        if let el = element(at: p) {
            moveAnchor = el.id
            let members = groupMembers(el.id)
            if !event.modifierFlags.isDisjoint(with: [.shift, .command]) {
                var sel = selection
                if sel.contains(el.id) { sel.subtract(members) } else { sel.formUnion(members) }
                setSelection(sel)
                if sel.contains(el.id) {
                    dragMode = .moving(origFrames: origFrames(for: sel))
                    beginGestureUndo("Move")
                } else {
                    dragMode = .idle
                }
            } else {
                if !selection.contains(el.id) {
                    setSelection(members)
                }
                dragMode = .moving(origFrames: origFrames(for: selection))
                beginGestureUndo("Move")
            }
            downPanelPoint = p
            didDrag = false
            return
        }

        // 3. Empty area → marquee (⇧ extends the current selection).
        let base = !event.modifierFlags.isDisjoint(with: [.shift, .command]) ? selection : []
        dragMode = .marquee(start: p, baseSelection: base)
        marqueeRect = CGRect(origin: p, size: .zero)
        downPanelPoint = p
    }

    private func origFrames(for ids: Set<UUID>) -> [UUID: CGRect] {
        var d: [UUID: CGRect] = [:]
        for el in document.elements where ids.contains(el.id) { d[el.id] = el.frame }
        return d
    }

    private func beginGestureUndo(_ name: String) {
        let old = document.elements
        edits.registerUndo(withTarget: self) { target in
            target.apply(elements: old, name: name)
        }
        suppressUndoRegistration = true
        lastUndoName = nil
    }

    private func endGesture() {
        suppressUndoRegistration = false
        lastUndoName = nil
    }

    override func mouseDragged(with event: NSEvent) {
        let p = panelPoint(from: event)
        let dx = p.x - downPanelPoint.x
        let dy = p.y - downPanelPoint.y
        if abs(dx) > 0.5 / zoom || abs(dy) > 0.5 / zoom { didDrag = true }

        switch dragMode {

        case .moving(let orig):
            // Snap the gesture once, from the element under the cursor, then
            // move everything by that same delta. Snapping each origin
            // independently pulls elements onto different grid points, so a
            // multi-selection drag silently destroyed any alignment between
            // them — which is exactly what "snap is messing up my alignment"
            // looks like from the outside.
            var sdx = dx, sdy = dy
            if let anchor = moveAnchor.flatMap({ orig[$0] }) ?? orig.values.first {
                switch snapMode {
                case .uniform:
                    sdx = snapVal(anchor.minX + dx) - anchor.minX
                    sdy = snapVal(anchor.minY + dy) - anchor.minY
                case .sergeGrid:
                    let center = CGPoint(x: anchor.midX + dx, y: anchor.midY + dy)
                    let snapped = snapEnabled ? SergeGrid.snapCenter(center, in: document) : center
                    sdx = snapped.x - anchor.midX
                    sdy = snapped.y - anchor.midY
                case .customGrid:
                    let center = CGPoint(x: anchor.midX + dx, y: anchor.midY + dy)
                    let snapped = snapEnabled ? CustomGrid.snapCenter(center, in: document) : center
                    sdx = snapped.x - anchor.midX
                    sdy = snapped.y - anchor.midY
                }
            }
            mutateFrames(orig) { frame in
                var nf = frame
                nf.origin.x = frame.minX + sdx
                nf.origin.y = frame.minY + sdy
                return nf
            }

        case .resizing(let dir, let orig, let rotation, let center):
            let localP = toLocal(p, rotation: rotation, center: center)
            let localDown = toLocal(downPanelPoint, rotation: rotation, center: center)
            let ldx = localP.x - localDown.x
            let ldy = localP.y - localDown.y
            var minX = orig.minX, minY = orig.minY
            var maxX = orig.maxX, maxY = orig.maxY
            let rawMinX = orig.minX + (dir == .nw || dir == .w || dir == .sw ? ldx : 0)
            let rawMaxX = orig.maxX + (dir == .ne || dir == .e || dir == .se ? ldx : 0)
            let rawMinY = orig.minY + (dir == .nw || dir == .n || dir == .ne ? ldy : 0)
            let rawMaxY = orig.maxY + (dir == .sw || dir == .s || dir == .se ? ldy : 0)
            if dir == .nw || dir == .w || dir == .sw { minX = min(snapVal(rawMinX), maxX - minSize) }
            if dir == .ne || dir == .e || dir == .se { maxX = max(snapVal(rawMaxX), minX + minSize) }
            if dir == .nw || dir == .n || dir == .ne { minY = min(snapVal(rawMinY), maxY - minSize) }
            if dir == .sw || dir == .s || dir == .se { maxY = max(snapVal(rawMaxY), minY + minSize) }
            let nf = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            updatePrimaryFrame(nf)

        case .marquee(let start, let base):
            let rect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                              width: abs(p.x - start.x), height: abs(p.y - start.y))
            marqueeRect = rect
            // Rubber-band hits expand to whole groups, so a marquee over part
            // of a group selects (and later moves) the group as one unit.
            let hitIDs = document.elements
                .filter { $0.isHidden != true && $0.isTemplate != true && $0.frame.intersects(rect) }
                .map(\.id)
            var hit = Set<UUID>()
            for id in hitIDs { hit.formUnion(groupMembers(id)) }
            selection = base.union(hit)
            needsDisplay = true

        case .groupResizing(let orig, let origFrames):
            let sx = orig.width > 0 ? max(0.05, (p.x - orig.minX) / orig.width) : 1
            let sy = orig.height > 0 ? max(0.05, (p.y - orig.minY) / orig.height) : 1
            var els = document.elements
            for i in els.indices where origFrames[els[i].id] != nil {
                let f = origFrames[els[i].id]!
                els[i].x = orig.minX + (f.minX - orig.minX) * sx
                els[i].y = orig.minY + (f.minY - orig.minY) * sy
                els[i].w = max(minSize, f.width * sx)
                els[i].h = max(minSize, f.height * sy)
            }
            document.elements = els
            needsDisplay = true
            notifyChange()

        case .groupRotating(let center, let startAngle, let origFrames, let origRotations):
            guard hypot(dx, dy) * zoom > rotateDeadZone else { break }
            var delta = (atan2(p.y - center.y, p.x - center.x) - startAngle) * 180 / .pi
            if event.modifierFlags.contains(.shift) { delta = (delta / 15).rounded() * 15 }
            if abs(delta) < rotateSnapToZero { delta = 0 }
            var els = document.elements
            for i in els.indices where origFrames[els[i].id] != nil {
                let f = origFrames[els[i].id]!
                let rc = Geo.rotate(CGPoint(x: f.midX, y: f.midY), around: center, degrees: delta)
                els[i].x = rc.x - f.width / 2
                els[i].y = rc.y - f.height / 2
                els[i].rotation = max(-180, min(180, (origRotations[els[i].id] ?? 0) + delta))
            }
            document.elements = els
            needsDisplay = true
            notifyChange()

        case .rotating(let origRotation, let center, let startAngle):
            // Dead zone. A click on the badge that drifts a pixel or two must
            // not impart a rotation too small to see but large enough to land
            // in the export as <g transform="rotate(-0.07 …)">.
            guard hypot(dx, dy) * zoom > rotateDeadZone else { break }
            let a = atan2(p.y - center.y, p.x - center.x)
            var deg = origRotation + (a - startAngle) * 180 / .pi
            if event.modifierFlags.contains(.shift) { deg = (deg / 15).rounded() * 15 }
            if abs(deg) < rotateSnapToZero { deg = 0 }   // let it pass cleanly through upright
            updatePrimaryRotation(max(-180, min(180, deg)))

        case .mirroring(let axis, let orig):
            let c = primaryElement?.center ?? downPanelPoint
            let crossed = axis == .x
                ? (p.x < c.x) != (downPanelPoint.x < c.x)
                : (p.y < c.y) != (downPanelPoint.y < c.y)
            updatePrimaryFlip(axis, orig != crossed)

        case .idle:
            break
        }
    }


    private func snapVal(_ v: CGFloat) -> CGFloat {
        snapEnabled ? Geo.snap(v, to: snapStep) : v.rounded(.toNearestOrAwayFromZero)
    }

    /// Snaps a *centre* point per the active snap mode. Used everywhere a
    /// placement is naturally described by its centre (stamp drops, palette
    /// drag-and-drop, "insert at panel centre").
    func snappedCenter(_ p: CGPoint) -> CGPoint {
        switch snapMode {
        case .uniform:
            return CGPoint(x: snapVal(Geo.snap(p.x, to: Geo.defaultSnap)),
                           y: snapVal(Geo.snap(p.y, to: Geo.defaultSnap)))
        case .sergeGrid:
            return snapEnabled ? SergeGrid.snapCenter(p, in: document) : p
        case .customGrid:
            return snapEnabled ? CustomGrid.snapCenter(p, in: document) : p
        }
    }

    /// Snaps a *centre* point, then converts to the top-left origin an
    /// element of `size` needs to be centred there.
    func snappedOrigin(forCenter point: CGPoint, size: CGSize) -> CGPoint {
        let c = snappedCenter(point)
        return CGPoint(x: c.x - size.width / 2, y: c.y - size.height / 2)
    }

    private func mutateFrames(_ orig: [UUID: CGRect], _ mapper: (CGRect) -> CGRect) {
        var els = document.elements
        for i in els.indices {
            if let o = orig[els[i].id] {
                els[i].frame = mapper(o)
            }
        }
        document.elements = els   // gesture path: no extra undo registration
        needsDisplay = true
        notifyChange()
    }

    private func updatePrimaryFrame(_ nf: CGRect) {
        var els = document.elements
        if let i = els.firstIndex(where: { $0.id == primaryElement?.id }) {
            els[i].frame = nf
        }
        document.elements = els   // gesture path: no extra undo registration
        needsDisplay = true
        notifyChange()
    }

    var selectionBounds: CGRect? {
        let sel = document.elements.filter { selection.contains($0.id) }
        guard let first = sel.first else { return nil }
        var b = first.frame
        for el in sel.dropFirst() { b = b.union(el.frame) }
        return b
    }
    private func frameMap() -> [UUID: CGRect] {
        var d: [UUID: CGRect] = [:]
        for el in document.elements where selection.contains(el.id) { d[el.id] = el.frame }
        return d
    }
    private func rotationMap() -> [UUID: CGFloat] {
        var d: [UUID: CGFloat] = [:]
        for el in document.elements where selection.contains(el.id) { d[el.id] = el.rotation }
        return d
    }

    private func updatePrimaryRotation(_ deg: CGFloat) {
        var els = document.elements
        if let i = els.firstIndex(where: { $0.id == primaryElement?.id }) {
            els[i].rotation = deg
        }
        document.elements = els   // gesture path: no extra undo registration
        needsDisplay = true
        notifyChange()
    }

    private func updatePrimaryFlip(_ axis: MirrorAxis, _ on: Bool) {
        var els = document.elements
        if let i = els.firstIndex(where: { $0.id == primaryElement?.id }) {
            if axis == .x { els[i].params.flipX = on } else { els[i].params.flipY = on }
        }
        document.elements = els   // gesture path: no extra undo registration
        needsDisplay = true
        notifyChange()
    }

    override func mouseUp(with event: NSEvent) {
        isGestureActive = false   // before the switch: the notifications below flush the layer list
        switch dragMode {
        case .marquee:
            // A click on empty canvas with no drag clears the selection.
            // Previously nothing happened unless the mouse moved far enough to
            // start a rubber band, so deselecting meant finding a blank patch
            // and twitching.
            if !didDrag { setSelection([]) }
            marqueeRect = nil
            needsDisplay = true
            onSelectionChange?()
        case .moving, .resizing:
            endGesture()
            if !didDrag, case .moving = dragMode, event.modifierFlags.isDisjoint(with: [.shift, .command]),
               let p = element(at: panelPoint(from: event)) {
                setSelection(groupMembers(p.id))
            }
            onSelectionChange?()
        case .groupResizing, .groupRotating:
            endGesture()
            onSelectionChange?()
        case .rotating:
            endGesture()
            onSelectionChange?()
        case .mirroring(let axis, let orig):
            endGesture()
            if !didDrag { updatePrimaryFlip(axis, !orig) }   // plain click toggles
            onSelectionChange?()
        case .idle:
            break
        }
        dragMode = .idle
    }

    func element(at p: CGPoint) -> PanelElement? {
        document.elements.reversed().first {
            $0.isHidden != true && $0.isTemplate != true && $0.contains(globalPoint: p)
        }
    }
}
