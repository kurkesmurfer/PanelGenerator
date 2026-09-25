# The PanelGenerator pipeline

How a VCV Rack panel gets from a drawing to a loadable module, what each file
owns, and the rules that bite when they are broken.

This document is the contract. If you are an AI agent picking up work on this
project, read it before touching anything — most of what follows was learned by
getting it wrong on a real two-module plugin, and none of it is guessable.

---

## 1. The loop

```
   Rack module (.cpp)  ──import──┐
                                 ↓
   hand-drawn panel  ────────► .panelgen ────emit────►  res/*.svg
                                 │                      <Plugin>Widgets.hpp
                                 │                      <Module>_panel.hpp
                                 │                             │
                                 └──────── compare ────────────┘
```

The `.panelgen` document is the **only source**. Artwork and headers are build
output: regenerate them, never edit them. `compare` is what proves the output
still matches the document it claims to come from.

Every direction of that diagram is implemented:

| you have | you get | command |
|---|---|---|
| a module's C++ | a document with its components, labels and artwork | `Import Module Code…` (⌥⌘I) |
| someone's panel SVG | a tracing template, or editable artwork | `Import SVG…` (⌘I) |
| a document | artwork, widget library, placement header | `--emit` |
| two of the above | a difference report | `--compare` |

`Import SVG…` skips `<defs>`, `clipPath`, `mask`, `marker`, `pattern`,
`filter` and `symbol` entirely rather than resolving what references them —
walking into a `<defs>` block would draw its contents as if they were real
visible artwork, which they are not. A warning fires only when one of these
actually held something (an empty `<defs/>`, routine cruft most exporters
leave behind, is silent) and names exactly what was found, e.g. `<defs>
(clipPath, linearGradient, stop)`.

Run `Scripts/flatten-svg.py <file.svg>` on the source first — it losslessly
removes the common, harmless case (defs nothing actually references, `<use>`/
`<symbol>` reuse, which it unlinks into real geometry) via Inkscape's CLI,
and reports exactly what's left, by tag and id, when something is genuinely
in use (a real clip, mask, gradient, pattern or filter). Those need a manual
call — a clip becomes a Boolean intersection with the shape it clips, a
gradient becomes a chosen flat colour — not something to guess at
automatically; the script's own output says which.

---

## 2. The three forms, and what each owns

A panel exists in three places at once. Keeping them honest is the whole job.

| form | owns | never owns |
|---|---|---|
| `.panelgen` | everything: geometry, colours, roles, identifiers | — |
| `res/*.svg` | how the panel looks | where the components are |
| `<Module>_panel.hpp` | component ids and their positions | how anything looks |

The module's own `.cpp` owns the sound and nothing else. It must **not** declare
its own `enum ParamId` — see §5.

---

## 3. What emit writes, and who may edit it

```
res/<ModuleSlug>.svg              regenerated   panel artwork (dark/default variant)
res/<ModuleSlug>-light.svg        regenerated   panel artwork, light variant --
                                                 only written for a themed document
                                                 (PanelDocument.lightBackground set)
res/<ModuleSlug>-components.svg   regenerated   helper.py positions layer
res/components/<widget>-*.svg     regenerated   custom widget artwork
<Plugin>Widgets.hpp               regenerated   widget classes + Rack aliases
<Module>_panel.hpp                regenerated   ids, positions, addComponents()
<Plugin>WidgetBase.hpp            WRITTEN ONCE  yours: shared widget policy
```

A document only gets a light variant once it declares one in the editor (View
▸ Theme / the Inspector's Theme section). Component positions are identical
between variants -- only panel colours differ, so `<Module>_panel.hpp` is
unaffected either way.

Headers go to `src/` when the output directory has one, beside `res/` when it
does not, so emitting into a plugin lands each where a plugin keeps it.

`<Plugin>WidgetBase.hpp` is the seam. Every generated widget derives from a
base declared there — `KnobBase`, `PortBase`, `SwitchBase`, `SliderBase`,
`PlainBase` — so anything a family shares (theme, shadow, tooltips, hover) has
a home that regeneration cannot reach. Emit creates it once and then never
touches it. Delete it to get a fresh one.

**The widget library is per plugin, not per module.** Two modules using the
same jack must compile to one struct loading one SVG. Emit builds it from every
panel of that plugin it can find: the ones in this run, plus any sibling
`.panelgen` declaring the same plugin slug.

---

## 4. Commands

```
PanelGenerator --emit <doc|folder> <outdir> [--theme dark|light|both]
PanelGenerator --compare <a> <b> [--tolerance <mm>] [--no-labels]
PanelGenerator --icon <doc> <out.png> [size]
PanelGenerator --selftest <dir>
```

`--theme` defaults to `auto`: always emits the dark/default SVG at its usual
name, and additionally emits the light one *only* if the document declares a
light variant. Pass `dark`, `light`, or `both` to force a specific selection
regardless of what the document declares (`light`/`both` on an untethemed
document just writes a light SVG identical to the dark one -- harmless, not
an error).

Either side of `--compare` may be a `.panelgen`, a module's `.cpp`, or an SVG
with a components layer.

In a plugin's Makefile:

```make
PANELGEN_DIR ?= ../../PanelGenerator
PANELGEN ?= $(shell ls -t $(PANELGEN_DIR)/.build/release/PanelGenerator \
                          $(PANELGEN_DIR)/.build/debug/PanelGenerator 2>/dev/null | head -1)

panels-check:                 # non-destructive: emit to a scratch dir, compare
panels-apply:                 # destructive: emit into the plugin
```

`panels-check` is the one for CI. It cannot pass against a stale file, because
each document stamps its own digest into the header generated from it.

---

## 5. Invariants

Each of these has drawn blood. They are not stylistic.

### Millimetres, not pixels

Rack panels are authored with the viewBox in **millimetres**
(`viewBox="0 0 71.12 128.5"`, `width="71.12mm"`). PanelGenerator works in
75-dpi pixels, where 1 HP is 15 px and a 3U panel is 380 px. The conversion is
`75/25.4 ≈ 2.953`.

Read a millimetre position as pixels and every component lands at a third of
its proper place. The importer takes the scale from the `width` attribute's
unit; a file without one is assumed to be pixels and says so.

### `Centered` is not decoration

`createParamCentered<T>(pos, …)` takes a **centre**.
`createParam<T>(pos, …)` takes a **top-left corner**. The offset between them
is the widget's own size, which lives in Rack's SVG for that type and is not
knowable from the source. Uncentred calls import at the corner given and are
reported by line number rather than silently offset by a guess.

### The generated enum owns the ids

`addComponents()` places against the enum declared in `<Module>_panel.hpp`,
whose order is the panel's **reading order** — not the order the controls were
written in. A module that keeps its own `enum ParamId` will compile and bind
every control to the wrong parameter, because the two enums declare the same
names with different values.

So the module does:

```cpp
#include "Muse_ND_panel.hpp"
using namespace Muse_NDPanel;      // ids unqualified, as Rack code expects
```

and declares no enum of its own.

### Identifiers are numbered per enum, not per panel

Rack keeps `ParamId`, `InputId`, `OutputId` and `LightId` apart, so
`ANIMATE_PARAM` and `ANIMATE_INPUT` are not a clash — a knob sharing a name
with the CV input that feeds it is how modules are named.

### One SVG per switch position

`app::SvgSwitch` holds a frame per position and picks between them by parameter
value. A button is the two-position case. Two things fail quietly here:

- **`momentary`** belongs only to a button. A momentary widget snaps back on
  mouse-up, so a three-position rotary declared momentary can never rest
  anywhere but position 0.
- **The parameter range lives in the module.** Three frames with a param still
  at 0…1 reaches two of them. `configSwitch(QUANT_PARAM, 0.f, 2.f, 0.f, …)`.
  Nothing in the widget can fix this, so the generated struct carries the call.

Also: the count of positions you draw and the Rack type you bind to must agree.
A button group with three positions bound to `VCVButton` draws a two-position
momentary button.

### Filenames come from the class, never the instance

`museui::KnobLarge` owns `knob-large-bg.svg` and `knob-large-fg.svg` whether it
is placed once or thirty times. The suffix belongs to the family: `-bg`/`-fg`
because `SvgKnob` composites two files, `-0…-n` because `SvgSwitch` indexes
frames, bare because `SvgPort` takes one.

The namespace never appears in a filename and does not need to:
`res/components/` under `asset::plugin(pluginInstance, …)` is already
plugin-scoped. The directory *is* the namespace.

### Slugs: use underscores

A module slug names the panel file **verbatim** (`res/<slug>.svg`) and the C++
identifiers derived from it (`<Slug>_panel.hpp`, `namespace <Slug>Panel`),
where a hyphen is not legal and becomes an underscore anyway. Choose the hyphen
and one panel is spelled two ways in one directory. Slugs are corrected on
entry; spaces become `_`.

**Plugin slug** names the shared widget library and its namespace, and comes
from `plugin.json`. **Module slug** names this panel's artwork, header and
namespace, and comes from `createModel`. One plugin, many modules.

### Labels are not identifiers

Three different things have been called "name":

| where | field | what it is |
|---|---|---|
| Component section | **Identifier** | `QUANT` → `QUANT_PARAM` in generated C++ |
| Text element | **Content** | the words drawn on the panel |
| Layer list | layer name | organisational; feeds the identifier only if Identifier is empty |

A fully labelled panel can have every component unnamed. Two commands bridge
them: **Name from Labels** turns labels into identifiers, and **Adopt
Identifiers…** copies them from another panel or module source, matching on the
label beside each control plus its role.

Adopt is what a redesign needs: a new layout has the same controls in different
places, so position cannot pair them, but the label under a knob says what the
knob is in both panels. Matching is exact, then punctuation-insensitive
(`LFO 1` = `LFO1`), then by shared leading run (`ANIM` = `ANIMATE`, floor three
characters). Every loose match is reported.

### Provenance

Every generated file carries:

```
// PanelGenerator-Source: Muse ND · 25 components · digest 4717c5f5
```

The digest is FNV-1a over identifier, role, widget type and position in
millimetres — the **contract**, not the artwork. Recolour the panel and it does
not change; move one jack 1.25 mm and it does. `--compare` reads it first and
says loudly when two files came from different panels, because a stale file
otherwise reads as a panel full of moved and missing components.

---

## 6. What the tool cannot do

Do not discover these by finding them missing:

- **No light/dark theme pair.** One background colour per document, so
  `createThemedPanel(light, dark)` cannot be regenerated. Running
  `panels-apply` on a themed plugin loses the light panel.
- **No gradients.** Fills are solid. An imported gradient flattens to grey.
- **No clip paths, masks, `<use>`, or embedded rasters** on import — each is
  skipped with a warning.
- **No CSS.** Presentation attributes and `style="…"` are read; a shape styled
  only by a class imports unfilled.
- **`<text>` on import arrives as outlines**, because every Rack panel has its
  labels converted already — nanosvg drops text.
- **Knob rotation is not exported.** Rack sweeps a knob from `minAngle` to
  `maxAngle` itself, so artwork is exported pointing up.

---

## 7. Conventions

- One `panels/` folder per plugin, inside that plugin's repository. The
  documents are source and belong in version control.
- **Name each document after its module slug**, so `panels/Muse.panelgen`
  pairs with `Muse_panel.hpp`. `panels-check` relies on it.
- One document per module. Two documents claiming one module slug overwrite
  each other's artwork and header; emit fails rather than letting that pass.
- Commit generated output only so a contributor without PanelGenerator can
  still build.

---

## 8. Verifying a change

`make selftest` runs the whole harness headless: persistence, export, symbols,
widgets, switch frames, comparison, identifier transfer, both importers, and
code generation. It writes `Docs/pg_demo.svg` and `.png` as a visual check.

For a change that touches generation, the stronger test is the round trip:

```
make emit DOC=<doc> OUT=build/check
make compare A=<doc> B=build/check/<Module>_panel.hpp NOLABELS=1
```

and, for a module that already exists, comparing the generated header against
the hand-written source it came from. That is what caught the per-panel
identifier numbering, and no unit test would have.
