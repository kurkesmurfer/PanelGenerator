# Symbol design language

Panel iconography for PanelGenerator. One `Symbol` element kind, one catalogue
(`SymbolCatalogue.swift`), one set of rules. The rules exist so that a symbol
drawn today and a symbol added next year look like they belong to the same
instrument.

## 1. Solid, not hairline

Every symbol is a **filled shape**. Nothing in the family is a stroked outline
in the exported SVG.

Two reasons, one aesthetic and one physical. LCARS is a language of solid
blocks and sweeps; a thin constant-weight outline reads as technical drawing
and fights the backdrop. And MetaModule rasterises the panel to 240 px for the
full 128.5 mm — a line that looks crisp at editing size is sub-pixel there and
vanishes.

Mechanically this is one step: a symbol is authored as a **centreline**, and
`CGPath.copy(strokingWithWidth:lineCap:lineJoin:miterLimit:)` converts it into
the filled outline that gets exported. Authoring stays simple — a polyline or a
sampled function — while the output is solid geometry.

## 2. The unit box

A symbol's geometry is written in a **unit box: 0…1 on both axes, y downward**,
matching panel space. `SymbolContext.at(t, v)` maps into it.

- `t` runs left to right and generally means *time* or *frequency*.
- `v` runs top to bottom: `v = 0` is the top of the box, `v = 1` the bottom.
  A waveform peak is a small `v`.

The box is mapped to the element's frame at draw time. Waveforms stretch to
whatever frame they are given; a symbol whose meaning depends on its
proportions sets `preservesAspect` and is drawn in the largest centred square
that fits.

## 3. Weight is relative

`params.weight` is the ribbon thickness **as a fraction of the symbol's short
side** — not an absolute pixel value. A sine at 12 px and the same sine at
120 px therefore have the same visual proportions. This is the difference
between a set that is scalable and one that is merely resizable.

- default `0.16`
- range `0.04 … 0.28`
- floor of `1.2` panel px (about 0.4 mm) so a small symbol never disappears

Keep one weight across a panel unless you mean to create a hierarchy. Mixed
weights read as inconsistency, not emphasis.

## 4. The inset rule

The content box is inset by **half the weight** on every side. A stroked
centreline extends half the weight beyond itself, round caps included, so this
is exactly the amount that guarantees the finished outline never crosses the
element's frame.

This is what makes the selection rectangle honest and alignment predictable —
what you see selected is what will be exported. The self-test asserts it for
every symbol in the catalogue, at maximum weight, in both a wide and a tall
frame.

Consequence when authoring: **use the full 0…1 range**. Do not add your own
margin; the inset already accounts for it, and a hand-rolled margin makes the
symbol shrink relative to its neighbours.

## 5. Terminals and joins

Round caps, round joins, everywhere. Square terminals belong to the elbow and
box primitives, which is the register PanelGenerator already uses for
structure. Keeping symbols round-terminated separates *iconography* from
*chrome* at a glance.

## 6. Parameters

A symbol declares up to four parameters. The slots are generic
(`symbolA`…`symbolD`, all normalised 0…1); what each one *means* is declared by
the symbol's `SymbolSpec.parameters` labels, and the inspector builds its rows
from that.

This is deliberate: adding a symbol to the catalogue requires no change to the
document model, no new Codable field, and no migration. A symbol that needs no
parameters declares four `nil`s and shows no sliders.

Normalise inside the centreline closure, and clamp there too — a slider at 0
must still produce sane geometry, not a degenerate path.

## 7. Naming

`id` is lowerCamelCase and permanent: it is what lands in the `.panelgen` file,
so renaming one silently changes every panel that used it. `name` is the label
and can be changed freely.

## Adding a symbol

1. Append a `SymbolSpec` to the right family array in `SymbolCatalogue.swift`.
2. Write the centreline against the unit box, using the full 0…1 range.
3. Declare parameter labels and defaults, four of each.
4. `make selftest` — geometry and containment are checked for every entry.

No other file needs to change. The palette, the inspector rows, the renderer
and both exporters pick it up from the catalogue.

## Current families

| Family | Symbols |
|---|---|
| Signal | sine, triangle, saw ↗, saw ↘, square, pulse (width), noise (density), sample & hold |
| Function | ADSR (A/D/S/R), AD, slew (rate), clock (divisions), gate (length) |
| Filter | low pass, high pass (cutoff, resonance), band pass (centre, Q), notch (centre, depth) |
| Mark | arrow (direction), mult (ways), sum, invert, patch ring, attenuverter (sweep), range bracket (depth), index ticks (count, centre mark) |
| Glyph | Ka, Ru, Te, Vo, Sha, Nu, Il, Qa, Zi, Ma, Ov, Ek, Da, Ti, Hu, Ro |

Forty-one symbols. Waveforms and marks stretch to their frame; glyphs and the
round marks set `preservesAspect` and are drawn in the largest centred square,
because a stretched letterform stops being a letterform.

## The glyph grammar

The sixteen glyphs are one writing system, not sixteen decorative marks. They
share a deliberately narrow vocabulary:

- a **spine** — one stroke through the centre, vertical or diagonal
- **attachments** landing on a 3 × 5 lattice: bars, chevrons, quarter-arcs
- **arcs of one radius**, so curvature reads as a single hand
- **dots**, which are a round cap on a stroke too short to see
- **never more than four strokes**, which keeps ink density even across the set

That last rule is what makes them sit together as text. A glyph with eight
strokes would read as an illustration next to one with two, however well drawn
it was on its own.

When adding to the set, work within the grammar rather than around it. A glyph
that needs a fifth stroke is usually two glyphs.
