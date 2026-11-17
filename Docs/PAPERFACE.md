# Paperface design language

After the Serge paper-faced panels as reissued for the 50th anniversary
(Helios, Paris Flash, Tempo di Roma). Reference renders live in
`~/Development/Paperface/` (2914 × 1198 px, 84 HP, 4U).

## Measurements

| | 4U source | 3U (× 0.726) |
|---|---|---|
| Cell pitch | 171 px = 25.4 mm | 18.44 mm |
| Grid top | 82 px | 8.8 mm |
| Line weight | 3 px ≈ 0.45 mm | 0.33 mm |
| Banana jack | 0.43 cell | 7.9 mm |
| Knob | 0.47 cell | 8.7 mm |
| Lamp | 0.29 cell | 5.3 mm |

Colours: face `#E9E3D8`, line `#797B7A`, ink `#222322`; jacks white
`#FFFFFF`, black `#1E1E1E`, red `#AD2B2B`, purple `#8569A6`, grey `#A3A39F`;
lamp `#EDB44F`; knob `#1D1E1C`; socket `#575756`. Type is Futura Medium,
uppercase, slightly tracked.

## Grid (View ▸ Snap Step ▸ Paperface Grid)

- **Rows:** six object rows at 15.5 mm + 19.25 mm steps (measured: object
  centres at 144.6 … 1041.7 px of 1198, 179.5 px pitch), and the five
  half rows between them. "Serge Grid: Outer Half-Step" adds one more half
  step above and below, as for the Serge grid.
- **Columns:** a whole number of HP apart, per document (`paperfaceColumnHP`,
  View ▸ Snap Step ▸ Paperface Column Pitch, 2–6 HP). The default 4 HP
  (20.32 mm) is the nearest whole-HP match to the near-square original cell
  (18.4 mm × 19.25 mm in 3U); an n-column module is n × 4 HP wide, with the
  first column half a pitch in. Half columns sit between.
- Snapping offers both tiers on every row (a half column on a main row too).

## Vocabulary

A cell's outline says what its control is:

- **Cell** — plain square; sections are runs of cells.
- **Dome** — arched top with a centre tick: an attenuator / attenuverter knob.
- **Scale − +** — the strip under a dome or above a funnel: bipolar range.
- **Roof** — a gable: a plain (unipolar) pot.
- **Label strip** — a name under a knob (FREQ, WINDOW).
- **Funnel** — lines from the top corners into a jack: an input fed from the
  strip above.
- **Diamond** — half-diamonds round a two-line spine: an output; stacked, the
  CV-Pro bus.
- **Connector** — a straight line: normalling between two jacks.

Jack colour is signal type: white 0–5 V CV, black audio / bipolar, red
trigger / logic, purple sync, grey special.

## In the editor

`Styles/Paperface.swift`: palette sections *Paperface · Hardware / Cells /
Glyphs & Text*. Cell shapes are `.path` elements in a unit box, so they stretch
with their frame and keep their line weight. Hardware styles are stored in
`params.knobStyle` (aliases `jackStyle`, `ledStyle`): banana jack 1,
scalloped knob 3, ring lamp 1, plain screw 1.

`PaperfaceTests.oscillator()` builds Helios's OSCILLATOR section as an 8 HP
panel from source-pixel measurements; `PG_PAPERFACE_DEMO=<path> swift test
--filter PaperfaceTests` saves it.

## Module title, frame, toggle

- **Title:** a panel property (Panel inspector ▸ Title), drawn by the design
  language: Paperface Futura Medium caps, cap height 2.0 mm, centred 4.9 mm
  down; Kurkesmurfer and Serge the SpaceTime lockup (logo 5.2 mm, gap 1.2 mm,
  Fraunces SemiBold, centred 5.8 mm down). Edit ▸ Make Module Title converts
  a hand-placed title label (and a logo beside it).
- **Frame:** top line 8.6 mm (first row − 6.9), bottom 121.375 mm (last row +
  half a row), and on six-row panels the double line 63.625 / 66.35 mm. Drawn
  green with the grid, snapped to by edges, Edit ▸ Fit Artwork to Frame, and
  a warning on export for cells outside it.
- **Toggle:** bat toggle on a hex nut (nut 6.58 × 5.79 mm, ball 2.45 mm),
  2- or 3-way; a custom switch (`PaperfaceToggle2/3`) with one SVG per
  position, emitted into the plugin's widget library.

## Push button

Measured on Tempo di Roma: grey bezel 9.2 mm (#BBBBBA, rim #8C8C8C), collar
#C6C6C5 at 0.74 of the diameter, red cap #CF2E26 at 0.62 (pressed: 0.58,
darker). Palette entry `pfButton`: a `pushButton` with `switchStyle` 1,
custom class `PaperfacePushButton`, `momentary = true`, frames
`paperface-push-button-0/1.svg`.
