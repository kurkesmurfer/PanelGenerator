# PanelGenerator — Implementation Plan

A native macOS (AppKit/Swift) prototype editor for **VCV Rack front panels**, with a
Star Trek: TNG / LCARS-flavoured design workflow: filled curved shapes as first-class
citizens, a drag-and-drop repository of synth primitives, and the native OS X colour
picker.

## Product requirements

| Requirement | Approach |
|---|---|
| Native OS X editor | Swift 5 + AppKit, no third-party deps, SPM build |
| Panels sized in HP, 1U / 3U high | VCV conventions: 1 HP = 15 px, 3U = 380 px, 1U = 127 px |
| Output SVG + PNG | One shared vector renderer → SVG path data + bitmap rasteriser |
| Drag-and-drop primitive repo (jacks, rotary knobs, sliders) | Sidebar palette → pasteboard drag → canvas drop |
| Shapes & fills for backdrops | Box (per-corner radii), Ellipse, Triangle, LCARS Elbow, Ring Sector — all filled bezier paths |
| Prominent filled curved shapes (TNG look) | Elbow + Ring-Sector + capsule/pill presets, LCARS colour swatch bank |
| Default OS X colour picker | `NSColorWell` everywhere colours are edited |
| Git repo, plan, implementation | This repo; phased commits |

## Architecture

```
Model (value types, JSON)
  PanelDocument ── [PanelElement ── ElementKind + ElementParams + ColorSpec]
        │
        ▼
Renderer (single source of truth)
  parts(for:) -> [ShapePart(path: CGPath, fill, stroke)]
        ├── CanvasView      (AppKit CGContext, interactive overlays)
        ├── PNGExporter     (NSBitmapImageRep @ arbitrary scale)
        └── SVGExporter     (CGPath → <path d="…"> walker)
```

Because canvas, PNG and SVG all consume the same `CGPath`s, exports can never drift
from what you see.

## Phases

- [x] P0 Scaffold: SPM package, Makefile, .app bundling script, git repo
- [x] P1 Core model: HP/U metrics, element catalogue, params, JSON persistence
- [x] P2 Renderer: primitives (jack, knobs, faders, LED, screw), LCARS shapes, text
- [x] P3 Exporters: SVG + PNG + headless `--selftest` harness
- [x] P4 UI: window layout, canvas (select/move/resize/marquee/snap/zoom/undo,
      z-order), drag-and-drop palette, inspector with `NSColorWell` + LCARS swatches,
      full menu bar
- [x] P5 Verification: compile clean, selftest artifacts, visual inspection of render
- [x] P6 Docs: README, demo assets, bundled .app script

## Deliberate prototype simplifications

- Single-window, single-document (no NSDocument autosave/version browsing yet).
- Rotation edited via inspector (no on-canvas rotate handle yet).
- Undo coalescing is time-window based; rapid slider bursts collapse sensibly.
- Copy/paste of elements deferred (⌘D duplicate covers the main flow).

## Roadmap after prototype

1. Freeform bezier shape authoring (draggable control points) on canvas.
2. Multi-select align/distribute; layer list with reordering.
3. Panel templates (common module layouts) + 1U strip presets.
4. Export variants: per-knob sprite sheets, MetaModule-friendly asset naming.
5. NSDocument migration, autosave, versions; custom .icns app icon.
6. Silkscreen helpers: measurement overlay, HP ruler, drill-size annotations.

## Import (in progress)

`File ▸ Import SVG…` covers three of the four ways in; see `Docs/IMPORT.md`.

- [x] SVG path data and transform lists → CGPath (`SVGPath.swift`), both
      directions honest against `PathSVG.d`.
- [x] Geometry import: rect/circle/ellipse recognised as parametric elements,
      everything else as a normalised `.path` element.
- [x] Tracing template mode: faint, unclickable, never exported.
- [x] helper.py components layer: roles by fill, identifiers from `data-name`,
      `#WidgetClass` suffix honoured.
- [x] **Component recovery from C++.** `CppImport` reads a ModuleWidget
      constructor: positions (mm2px or px), widget types, identifiers, module
      slug and the panel resource. Resolves named constants from sibling
      headers and simple arithmetic; takes the Rack branch of an
      `#ifdef METAMODULE` fork. Uncentred `createParam` calls are placed at the
      corner given and reported by line number rather than offset by a guessed
      widget size.

- [ ] Gradients in the renderer. Still the one thing that stops Muse's
      `knob-large-bg.svg` round-tripping, and now also the reason an imported
      gradient flattens to grey.
