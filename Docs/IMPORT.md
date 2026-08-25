# Importing existing panels

`File ▸ Import SVG…` (⌘I) reads a panel SVG that PanelGenerator did not draw:
someone else's module, a hardware faceplate traced in Inkscape, or your own
earlier artwork.

Two modes, chosen in the import dialog.

## As a tracing template

Everything comes in as **template artwork**: drawn at 35 % on the canvas, not
clickable, excluded from Select All, and never written to an exported SVG or
PNG. Draw your own panel over it in the LCARS language, then delete it from the
layer list — which is the one place a template can still be selected.

This is the mode to use when the answer to "can we import this panel?" is
really "I want to make my version of that panel".

## As editable artwork

Shapes become real elements, with one honest limitation:

| In the file | Comes in as |
|---|---|
| `<rect>`, with or without `rx` | **Box**, corner radii intact |
| `<circle>`, `<ellipse>` | **Ellipse** |
| `<path>`, `<polygon>`, `<polyline>`, `<line>` | **Imported Path** |
| a rotated or skewed rect or circle | **Imported Path** |

An Imported Path can be moved, scaled, rotated and recoloured. It has no
parameters, because the input has none: a bezier blob does not carry the fact
that it was once an elbow. If you need to change its shape, redraw it with the
shape tools and delete the import.

The path is stored normalised into a 0…1 box, so the element's frame scales the
artwork the way it does for every other kind, and it exports again through the
same writer that produced it.

## Components

A panel drawn for Rack's `helper.py` carries a layer named `components` whose
shapes are classified by fill:

| Fill | Role |
|---|---|
| `#ff0000` | param |
| `#00ff00` | input |
| `#0000ff` | output |
| `#ff00ff` | light |
| `#ffff00` | custom widget |

Those come in **bound**, with `data-name` as the identifier. `data-name` may
also carry a Rack type — `OUT#PJ3410Port` — and that becomes the element's
stock widget. Where it does not, the role picks the ordinary type
(`PJ301MPort`, `RoundBlackKnob`, `MediumLight<RedLight>`).

Check the roles afterwards. helper.py classifies by colour and nothing else, so
a panel whose author was careless about green and blue will import with its
inputs and outputs swapped — exactly the mistake that is invisible until a
patch cable refuses to connect.

## Units

This is the part that goes wrong silently everywhere else. Rack panels are
normally authored with the viewBox **in millimetres**:

```
<svg width="71.12mm" height="128.5mm" viewBox="0 0 71.12 128.5">
```

PanelGenerator works in 75-dpi pixels, where 1 HP is 15 px. The importer reads
the `width` attribute's unit and scales by it — 75/25.4 ≈ 2.953 for millimetres.
A file with no `width` is assumed to be in pixels already, and says so in the
import report.

The panel's HP is rounded from the result; if the file is not a whole number of
HP wide, the report says by how much.

## What does not survive

Each of these produces a warning in the import report rather than a silently
wrong drawing:

- **Gradients.** PanelGenerator fills are solid. A gradient fill imports as
  flat grey.
- **Clip paths, masks, markers, patterns, filters, `<symbol>`.** The subtree is
  skipped, so artwork that depended on it will differ.
- **`<use>`.** References are not resolved; that artwork is missing.
- **Embedded rasters.**
- **CSS in `<style>` blocks.** Presentation attributes and `style="…"` on the
  element are read; a shape styled only by a class comes in unfilled.
- **`<text>`.** No Rack panel has any — nanosvg drops text, so every panel in
  the wild already has its labels converted to outlines. Those import as paths,
  which means an imported panel's labels are shapes, not editable text. Retype
  them.

## Reading positions out of a plugin

`File ▸ Import Module Code…` (⌥⌘I) reads a `ModuleWidget` constructor. For
adopting an existing module this is the file that matters — the SVG carries the
artwork, the C++ carries everything else:

```cpp
addParam(createParamCentered<RoundBlackKnob>(mm2px(Vec(15.24, 38.95)), module, Module::CUTOFF_PARAM));
```

One pass gives the position, the widget type and the identifier. If the source's
`setPanel` names an SVG that sits beside it — in `res/` next to the file or one
level up — the import offers to bring the artwork in at the same time.

### What it understands

- `createParam` / `createInput` / `createOutput` / `createLight`, with and
  without `Centered`, plus `createWidget` for screws and other decoration.
- `mm2px(Vec(x, y))` and bare `Vec(x, y)` in panel pixels. Mixing these up is
  the mistake that puts every component at a third of its proper place.
- Arithmetic: `RACK_GRID_WIDTH * 2`, `7.0f`, `panelW / 2`, `(a + b) * -1`.
- **Named constants**, including from a sibling header. A panel laid out on a
  grid — `mm2px(Vec(7.0f, grid::PRIMARY_Y))` — is unreadable without them, so
  every `.h`/`.hpp` in the same directory is scanned for `constexpr`, `const`
  and `#define` values. Qualified names resolve by their last component.
- Nested widget templates: `MediumLight<GreenRedLight>` survives verbatim.
- **Namespaced types are your own widgets.** `museui::IoJack` imports as a
  custom widget named `IoJack`, not as a substituted Rack part, so generating
  code again names it correctly.
- `createModel<Module, Widget>("Slug")` for the module slug.
- **Labels drawn from code.** A panel's text is often not in its SVG at all —
  Muse draws every label with `museui::addCvLabel(this, 7.0f, grid::LABEL_Y,
  "X CV")`. Any call shaped *(literally `this`, a number, a number, a string)*
  is read as a label, centred on that position. The shape is what identifies
  them, not the name, and it is tight enough that a draw call like
  `nvgText(args.vg, x, y, "…")` cannot match. The font size is read from the
  helper's own definition where it is the usual one-line forwarder
  (`addLabel(w, x, y, text, font, 7.5f, …)`); otherwise it defaults and the
  report says so.
- `#ifdef METAMODULE`, resolved to the **Rack** branch. A ported module keeps
  both builds in one file, and reading both would import the panel twice.
  Other conditionals keep their first branch and say so.

### The `Centered` distinction

`createParamCentered<T>(pos, …)` takes a centre. `createParam<T>(pos, …)` takes
a **top-left corner**, and the offset between the two is the widget's own size —
which lives in Rack's SVG for that type, not in the source and not here.

Uncentred calls are placed at the corner as given, at PanelGenerator's default
size for the kind, and each one is reported with its line number. The
alternative — a table of ComponentLibrary sizes — is more accurate on the day
it is written and goes stale without telling anyone. Screws are exempt from the
warning: `createWidget` is always corner-positioned, and flagging every one of
them would bury the cases that matter.

### What it does not do

It is a reader, not a compiler. Positions built from anything it cannot
evaluate — a function call, a member lookup, a loop counter — are skipped, with
the line number and the expression in the report. A module that places its
widgets in a `for` loop will import with holes; those are the ones to place by
hand.
