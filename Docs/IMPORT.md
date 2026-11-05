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

PanelGenerator works in 75-dpi pixels, where 1 HP is 15 px. A physical `width`
(mm, cm, in, pt) settles the scale. When the file gives no width, or a width in
pixels, the importer checks whether that yields a real Eurorack height (3U, or a
Pulp Logic / Intellijel 1U strip). If not, it tries millimetres, Illustrator's
points (72 dpi) and web pixels (96 dpi) and takes the one whose height *and*
whole-HP width fit, saying so in the report. A file with only `width` and
`height` and no viewBox is read as CSS pixels at those sizes.

The panel's HP is rounded from the result; if the file is not a whole number of
HP wide, the report says by how much.

## Styles, references and hidden layers

- **CSS** in `<style>` blocks applies, for the selectors panel files use:
  `.class`, `#id`, `tag`, `tag.class`, `*`. The cascade is the spec's:
  presentation attributes, then rules by specificity, then `style="…"`.
- **Hidden layers stay out.** `display:none` and `visibility:hidden` (a hidden
  Inkscape layer) are not imported; the report counts them. The one exception is
  helper.py's `components` layer, which is normally hidden and is always read.
- **`<use>` and `<symbol>`** are resolved, including a symbol's viewBox scaled
  to the use's width and height.
- **Clip paths** are applied: the clipped geometry is intersected with the clip.
  A shape entirely outside its clip is left out and counted.
- **fill-rule:evenodd** is kept, by normalising the path so holes survive the
  non-zero fill PanelGenerator draws with.
- **Opacity** multiplies down the tree into the fill and stroke alpha.
- **Colours**: every CSS form — `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`,
  `rgb()`/`rgba()` with numbers or percentages, `hsl()`, all 147 named colours
  and `currentColor`. An unrecognised colour draws black and is named in the
  report rather than making the shape disappear.
- **Malformed path data** is drawn up to the first error, as browsers do.

## What does not survive

Each of these produces a warning in the import report rather than a silently
wrong drawing:

- **Gradients** come in as their average colour; PanelGenerator fills are solid.
- **Masks, filters (shadows, blurs, glows) and pattern fills** are named in the
  report and not applied.
- **Embedded rasters.**
- **Multi-line text** split across positioned `<tspan>`s comes in as one line.

To see what an import will do before opening it, or across a whole folder of
panels:

```
PanelGenerator --import-check <file.svg|file.cpp|folder> [png-folder]
```

prints what each file imports as and every warning, and optionally renders each
import to PNG.

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
  the mistake that puts every component at a third of its proper place. Also
  `Vec(mm2px(x), mm2px(y))` and helpers such as `millimetersToPixelsVec(x, y)`.
- Arithmetic: `RACK_GRID_WIDTH * 2`, `7.0f`, `panelW / 2`, `(a + b) * -1`.
- **Named constants**, including from a sibling header. A panel laid out on a
  grid — `mm2px(Vec(7.0f, grid::PRIMARY_Y))` — is unreadable without them, so
  every `.h`/`.hpp` in the same directory is scanned for `constexpr`, `const`
  and `#define` values, including several per declaration
  (`constexpr float X0 = 9.4f, PITCH = 11.f;`) and arrays
  (`laneY[5] = {…}`, used as `laneY[3]`). Qualified names resolve by their
  last component.
- **Locals, in order.** `float y = 30.f;` before one call and `y = 50.f;` or
  `y += 10.f;` before the next give each call its own value.
- **Loops with constant bounds are unrolled**, nested ones too:
  `for (int i = 0; i < 4; i++) addInput(… Vec(X0 + i * PITCH, Y) …, IN_INPUT + i)`
  gives four jacks named `IN_1` … `IN_4`.
- Casts: `(float) x`, `float(x)`, `static_cast<float>(x)`.
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
evaluate — a function call, a member lookup, a loop whose bound is not a
constant — are skipped, with the line number and the expression in the report;
those are the ones to place by hand. `box.size.x` (right-hand screws) resolves
when the panel SVG that `setPanel` names is found beside the source.
