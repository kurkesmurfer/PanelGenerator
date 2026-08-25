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

## Reading positions out of a plugin instead

For adopting an existing module, the SVG is usually the wrong file. Component
positions live in the C++:

```cpp
addParam(createParamCentered<RoundBlackKnob>(mm2px(Vec(15.24, 38.95)), module, Module::CUTOFF_PARAM));
```

That gives positions, widget types and identifiers in one pass, where the SVG
gives only artwork. A reader for that is a separate pass — see PLAN.md.
