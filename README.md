# PanelGenerator

**A native macOS editor for designing VCV Rack front panels — with a Star Trek:
TNG / LCARS soul.**

Filled curved shapes are first-class citizens: LCARS elbows, sweeping ring
sectors, and per-corner-radius boxes (pills & capsules) sit right next to the
synth primitives — jacks, rotating knobs, and faders — in a drag-and-drop
repository. Colours are edited with the **native macOS colour picker**
(`NSColorWell`), backed by a curated Okudagram swatch bank.

![Demo panel](Docs/pg_demo.png)

## Features

- **Panels in HP × U** — width in HP, height 1U or 3U, using VCV Rack's SVG
  conventions (1 HP = 15 px, 3U = 380 px, 1U = 127 px) so exports drop
  straight into Rack-sized layouts.
- **Drag-and-drop repo** — jacks, knobs (L/M/S with rotatable pointer),
  vertical/horizontal faders, LEDs, screws, text labels; plus the shape kit:
  box (per-corner radii), ellipse, triangle, LCARS elbow (thickness, inner
  radius, arm lengths, mirror/flip), ring sector (start/sweep/thickness).
- **Real editing** — click / shift-click / marquee selection, move & resize
  with HP-grid snapping, rotation, z-order, duplicate, delete, full undo/redo,
  zoom (fit / actual / in / out).
- **One vector truth** — canvas, PNG and SVG all consume the same `CGPath`
  data; exports can never drift from what you see.
- **Export** — SVG (vector, Rack-compatible px space) and PNG at 4×
  (720×1520 for a 12HP 3U panel).
- **Documents** — JSON `.panelgen` files; Open/Save/Save As with dirty-state
  prompts.
- **Headless smoke test** — `PanelGenerator --selftest [dir]` renders a
  showcase panel to SVG+PNG without a window server.

## Build & run

Requires macOS 13+ and Xcode command line tools.

```bash
make run        # build debug + launch the editor
make app        # build release + assemble PanelGenerator.app, then: open PanelGenerator.app
make selftest   # headless render test → Docs/pg_demo.{svg,png}
```

Or plain SPM: `swift build && .build/debug/PanelGenerator`.

## Using the editor

1. **Drag** a primitive or shape from the left repo onto the panel
   (double-click drops it centred).
2. Select and edit in the right inspector: position, size, rotation, fill
   (native colour picker + LCARS swatches), stroke, and per-kind parameters
   (knob pointer angle, fader value, corner radii, elbow geometry, ring
   angles, text content).
3. Compose the backdrop first (big elbows + ring sectors + capsules read as
   instant TNG), then place controls on top.
4. **File ▸ Export SVG… / Export PNG…**.

### Shortcuts

| Action | Keys |
|---|---|
| Undo / Redo | ⌘Z / ⇧⌘Z |
| Duplicate / Delete | ⌘D / ⌫ |
| Select all | ⌘A |
| Zoom in / out / actual / fit | ⌘= / ⌘− / ⌘0 / ⌘9 |
| Toggle snap-to-grid | ⇧⌘G |
| New / Open / Save | ⌘N / ⌘O / ⌘S |
| Export SVG / PNG | ⌘E / ⇧⌘E |

## Architecture

```
Model (value types, JSON)           Geometry: 1HP=15px · 3U=380px · 1U=127px
  PanelDocument → [PanelElement]
        │
        ▼
Renderer — parts(for:) -> [ShapePart(CGPath, fill, stroke)]   ← single source of truth
        ├── CanvasView        interactive AppKit surface + overlays
        ├── PNGExporter       CGContext over NSBitmapImageRep, 4×
        └── SVGExporter       CGPath → <path d="…"> walker (PathSVG)
```

Source layout: `Sources/PanelGenerator/` — `Model.swift`, `Geometry.swift`,
`Renderer.swift`, `PathSVG.swift`, `Exporters.swift`, `CanvasView.swift`,
`PaletteView.swift`, `InspectorView.swift`, `MainWindowController.swift`,
`AppDelegate.swift`, `Selftest.swift`, `main.swift`.

## Status & roadmap

This is a **prototype** (see `PLAN.md` for the phase log and deliberate
simplifications). Next up, in rough order: freeform bezier shape authoring
with draggable control points, multi-select align/distribute, a layer list,
panel templates, and NSDocument migration (autosave + versions).

## License

MIT — see [LICENSE](LICENSE).
