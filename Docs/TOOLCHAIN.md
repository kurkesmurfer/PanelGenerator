# Toolchain

How a PanelGenerator document reaches a plugin.

## Where things live

The `.panelgen` is **source**, not a scratch file. It is the origin of the
panel artwork *and* of the layout code, so it belongs in the plugin's own
repository — otherwise the plugin cannot rebuild itself without a copy of
somebody's editor folder.

```
Muse/                              the plugin repository
  panels/
    Muse.panelgen                  source, tracked
    MuseXT.panelgen
    Muse-ND.panelgen
  vcv/
    plugin.hpp  plugin.json
    MuseND.cpp                     yours: module, DSP, createModel
    Muse_ND_panel.hpp              GENERATED — never edit
    res/
      Muse-ND.svg                  GENERATED
      Muse-ND-components.svg       GENERATED (helper.py input; optional)
      components/*.svg             GENERATED, custom widget artwork
  metamodule/
    assets/…                       rasterised from vcv/res by the existing scripts
```

PanelGenerator itself holds no per-plugin state. It is a tool the plugin
calls, in the same slot `generate_vcv_panels.py` occupies today.

## The one command

```
PanelGenerator --emit panels/ vcv
```

A directory emits every document in it, so a plugin with three modules
regenerates in one step. A single file works too:

```
PanelGenerator --emit panels/Muse-ND.panelgen vcv
```

Output paths are relative to the second argument: `vcv/res/<ModuleSlug>.svg`
and `vcv/<ModuleIdentifier>_panel.hpp`. That is why the second argument is the
plugin's source directory and not a staging area — there is nothing to copy
afterwards, and therefore no copy step to forget.

## In the plugin's Makefile

```make
PANELGEN ?= $(HOME)/Development/PanelGenerator/.build/release/PanelGenerator

.PHONY: panels
panels:
	$(PANELGEN) --emit panels/ vcv

# MetaModule PNGs follow from the same artwork
.PHONY: assets
assets: panels
	metamodule/scripts/build_panels.py
	metamodule/scripts/build_components.py
```

Make `panels` a prerequisite of the plugin build if you want artwork and code
regenerated on every build; leave it manual if you would rather see the diff
before it lands.

## What is generated and what is yours

| File | Owner | Regenerated |
|---|---|---|
| `panels/*.panelgen` | you, in the editor | never |
| `vcv/res/<Slug>.svg` | generator | every emit |
| `vcv/res/components/*.svg` | generator | every emit |
| `vcv/<Module>_panel.hpp` | generator | every emit |
| `vcv/<Module>.cpp` | you | never |
| `vcv/plugin.json` | you | never (the header prints the fragment to paste) |

The split is the point. The header holds enums, custom widget structs and one
`addComponents(widget, module)` entry point, and carries a do-not-edit banner.
Your module source includes it and calls it:

```cpp
#include "plugin.hpp"
#include "Muse_ND_panel.hpp"

struct MuseND : Module {
    MuseND() {
        config(Muse_NDPanel::PARAMS_LEN, Muse_NDPanel::INPUTS_LEN,
               Muse_NDPanel::OUTPUTS_LEN, Muse_NDPanel::LIGHTS_LEN);
    }
    void process(const ProcessArgs& args) override { /* yours */ }
};

struct MuseNDWidget : ModuleWidget {
    MuseNDWidget(MuseND* module) {
        setModule(module);
        Muse_NDPanel::addComponents(this, module);
    }
};

Model* modelMuseND = createModel<MuseND, MuseNDWidget>("Muse-ND");
```

Move a knob, run `make panels`, rebuild. Nothing of yours is at risk, and
there is no merge — which is the whole reason the layout is a header rather
than fragments to paste.

## Should the generated files be committed?

Yes. A contributor without PanelGenerator can then still build the plugin, and
the diff on a regenerated header is a readable record of what moved. The cost
is noise in the history when a panel is being iterated; commit the document and
its output in the same commit and that noise stays legible.

## MetaModule

No separate element array is needed when the MetaModule build compiles the same
VCV sources through the SDK's rack adaptor — it reads the elements from the
ModuleWidget. What differs is artwork: mirror `vcv/res` into
`metamodule/assets` as PNGs. `build_components.py` requires `width="…mm"` on
each component SVG, which is why PanelGenerator exports millimetres by default.

## Checking that the three forms still agree

A panel exists in three places at once — the `.panelgen` document, the exported
artwork, and the module's C++ — and nothing stops them drifting apart. Diffing
the files by hand does not work: the same position is written three different
ways and the ordering is not stable between them.

```
make compare A=~/Development/Muse/vcv/Muse.cpp B=Panels/Muse.panelgen
.build/debug/PanelGenerator --compare <a> <b> [--tolerance <mm>] [--no-labels]
```

Either side may be a `.panelgen`, a module's `.cpp`, or an SVG with a
components layer — the same three readers the importers use. Each side is
reduced to identifier, role, widget type and centre in millimetres, matched by
identifier, and reported as:

| | |
|---|---|
| **moved** | matched by identifier, position differs by more than the tolerance |
| **role changed** | param ↔ input ↔ output. The one that matters most: an output read as an input is the bug that surfaces as a patch cable that will not connect |
| **widget changed** | a different Rack type or custom widget |
| **renamed** | same position, different identifier — one edit, not a deletion plus an addition |
| **only in A / only in B** | present on one side |

Labels are compared too, matched by their words and then nearest-first, so a
panel with four jacks all labelled "CV" does not shuffle them. `--no-labels`
turns that off.

The default tolerance is 0.01 mm. Zero would be wrong: the three forms round
differently — the C++ carries whatever the author typed, the document holds
panel pixels, the SVG holds two decimals — so an exact match would report every
component as moved. A hundredth of a millimetre is far below anything a panel
can express.

Exit code is 0 when the two agree and 1 when they do not, so it drops straight
into a plugin's Makefile as a check rather than a chore.

Anything a reader could not resolve is printed as a **note** rather than a
difference. That distinction matters: a component the C++ reader skipped would
otherwise appear as "missing", and knowing it was skipped rather than absent is
the difference between a bug in the panel and a gap in the reader.

## Switches and buttons

Rack draws both with `app::SvgSwitch`, which holds **one SVG per position** and
picks between them by parameter value. A button is the two-position case of the
same widget.

PanelGenerator exports a frame per position — `switch3-way-0.svg`,
`-1.svg`, `-2.svg` — by rendering the control once per position with the toggle
moved. On the canvas, **Position** in the inspector selects which one you are
looking at; a composed switch keeps its housing in every frame and moves only
the anchor.

Two things decide whether the result actually works in Rack, and both fail
quietly:

**`momentary`** is generated only for a button. A momentary widget snaps back
on mouse-up, so a three-position rotary declared momentary can never rest
anywhere but its first position — it looks like a switch that refuses to move.

**The parameter range lives in the module, not in the widget.** A switch with
three frames whose param is still the default 0…1 can only ever reach frames 0
and 1. Nothing in the generated widget code can fix that, so the generated
struct carries the call you need:

```cpp
configSwitch(QUANT_PARAM, 0.f, 2.f, 0.f, "Quant", {"Free", "JI", "Octave"});
```

and the export report warns about every switch with more than two positions.
This is the failure that reads as broken artwork when it is a missing line of
module code.
