# PanelGenerator — guidance for Claude Code

Native macOS (Swift 5.9+/AppKit, SPM, no third-party deps) editor for VCV Rack
and MetaModule front panels. A `.panelgen` document (JSON) is the single source
for panel artwork (SVG/PNG), widget C++ and the MetaModule mm table. Three
design languages: **Kurkesmurfer** (house style), **Serge** (paperface grid)
and **LCARS**. Owner: Peet (kurkesmurfer). Repo:
https://github.com/kurkesmurfer/PanelGenerator (public).

Read first: `README.md` (features, layout), `PIPELINE.md` (panel ↔ code
contract, `--emit`/`--compare`), `Docs/TOOLCHAIN.md`, `Docs/SYMBOLS.md`.

## State at handoff (25 Sep 2026)

- `main` = pre-refactor code, all work up to 11 Sep committed.
- **PR #14** `refactor/panelkit` → main: PanelKit library target + PanelKitTests.
- **PR #15** `refactor/styles` → `refactor/panelkit` (stacked): Model/Render/
  Symbols/Styles split, UI split, PanelCanvas module, CI, this file.
  Merge #14 first, then retarget #15 to `main`.
- Peet has run the refactored app on a real document (demon.panelgen) without
  problems. CI (`.github/workflows/ci.yml`, macos-26) is green on #15.
- Work is tracked in GitHub issues. Milestone **M1 Library refactor**: #9
  (tests for `--theme` variant selection and rotation-aware resize), #10
  (comment hygiene), #11 (docs drift: PLAN.md, README roadmap). Milestone
  **M2 Editor quirks**: #7 (snap mode defaults to the Serge grid and is not
  saved), #8 (stringly-typed align/distribute), #12 (TODO in generated slider
  code), #13 (triage leftovers from CODE_REVIEW.html). Peet's own UI quirks go
  into M2 as new issues.

## Build, test, verify

```
make build        # swift build
make test         # swift test — 42 XCTests, incl. every --selftest group
make selftest     # headless render → Docs/pg_demo.{svg,png}
make identical    # refactor guard, see below
make app          # release build + PanelGenerator.app (icon, stamps, manual)
```

**Refactors must be behaviour-neutral, and that is checked, not assumed:**
`make identical [BASE=<ref>]` (Scripts/check-identical.sh) builds BASE
(default `main`) in a temporary worktree and diffs `--selftest`,
`--emit --theme both` for every `Panels/*.panelgen`, `--compare`, `--icon` and
`--grid` byte for byte. Run it before every refactor commit. Every commit
should build on its own.

The GUI cannot be tested headless. After UI changes, launch the app and ask
Peet to check the affected interactions by hand.

## Layout and boundaries

```
Sources/PanelKit/        library, no windows: Model/, Render/, Styles/, Symbols/,
                         Geometry, SVG/C++ import, export, CodeGen, Compare,
                         Emit, Stamps, Selftest
Sources/PanelCanvas/     CanvasView (+Clipboard, +Commands, +Drawing, +Handles,
                         +Mouse, +DragDrop)
Sources/PanelGenerator/  editor: InspectorView(+…), MainWindowController(+…),
                         PaletteView, LayerListView, SymbolPicker, AppDelegate,
                         main.swift (CLI: --emit --compare --icon --grid --selftest)
Tests/PanelKitTests/
```

- **Access levels.** Cross-target API is `package`, never `public`. Inside
  PanelCanvas, gesture/handle/snapping state is plain `internal` and must stay
  invisible to the editor. Only promote a member to `package` when the editor
  needs it. `selection` and `isGestureActive` are `package internal(set)`.
- Dependencies: PanelGenerator → PanelCanvas → PanelKit. The canvas must not
  reference inspector, window or palette types.
- **Design languages** live in `Sources/PanelKit/Styles/`. `DesignLanguage.all`
  is the registry (palette order); `DesignLanguage.swatchBank` fixes the
  inspector's swatch order. A new style is one file plus one line there.
  Colour defaults cite swatches by name: `ColorSpec.swatch("Orange")`.
- **Preset ids** (`delineationKM`, `bracketSerge`, `connectorSerge`, `ring`, …)
  travel on the pasteboard as `kind#preset`. Never rename them. StyleTests
  require every palette preset to have exactly one owner.

## Swift gotchas already hit here

- `ColorSpec` collides with QuickDraw's `ColorSpec` across module boundaries.
  Each non-PanelKit module pins it in `PanelKitNames.swift`
  (`typealias ColorSpec = PanelKit.ColorSpec`).
- Synthesised `CodingKeys` are file-private. A type's tolerant
  `init(from:)` (via `decodeOr`) must stay in the type's own file.
- **Model changes:** every new stored field needs a `decodeOr(…, default)`
  entry in that type's `init(from:)`, or older `.panelgen` files stop
  opening. Bump `PanelDocument.currentSchemaVersion` when the meaning of saved
  data changes. The legacy-document selftest guards this.
- `private` / `private(set)` are file-scoped. Across a class's extension files
  use `internal` (or `package internal(set)` in PanelCanvas).
- Structs used across modules need explicit `package init` (memberwise inits
  are internal).
- VCV Rack's nanosvg ignores `<text>`, so text is exported as outlines. Keep
  `textAsPaths` on for Rack output.

## Conventions

- Commits: conventional prefix (`feat(scope):`, `fix:`, `refactor:`, `test:`,
  `docs:`, `ci:`, `chore:`), body explains *why*, reference issues
  (`Closes #n`, `Refs #n`). Work on a branch and open a PR. Never push to
  `main` directly.
- Comments state the rule and the reason. History ("X asked for…", "confirmed
  on …") belongs in commit messages (see #10). British spelling in prose
  (colour, centre) matches the codebase.
- Peet prefers direct, professional communication and challenges where there
  is reasonable doubt. Don't guess at his hardware or design intent: ask.
- If `git` reports `index.lock` exists and no git process is running, the
  lock is stale (one blocked commits for two weeks); remove it.
- `_to_delete/` and `build/` are ignored scratch; don't commit from them.
