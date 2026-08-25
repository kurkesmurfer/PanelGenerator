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
