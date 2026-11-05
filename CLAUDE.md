# PanelGenerator — guidance for Claude Code

Native macOS (Swift 5.9+/AppKit, SPM, no third-party deps) editor for VCV Rack
and MetaModule front panels. A `.panelgen` document (JSON) is the single source
for panel artwork (SVG/PNG), widget C++ and the MetaModule mm table. Three
design languages: **Kurkesmurfer** (house style), **Serge** (paperface grid)
and **LCARS**. Owner: Peet (kurkesmurfer). Repo:
https://github.com/kurkesmurfer/PanelGenerator (public).

Read first: `README.md` (features, layout), `PIPELINE.md` (panel ↔ code
contract, `--emit`/`--compare`), `Docs/TOOLCHAIN.md`, `Docs/SYMBOLS.md`.

## State (5 Nov 2026)

A stack of PRs, each based on the one before; merge in order, retargeting
each to `main` as the one below it lands:

1. **#14** `refactor/panelkit` — PanelKit library + tests
2. **#15** `refactor/styles` — per-concern files, design languages, UI split,
   PanelCanvas module, CI
3. **#17** `feat/replace-with` — Replace With / ⌘-drop
4. **#22** `fix/import` — SVG reader rewrite (CSS, use/symbol, clips, hidden
   layers, gradients, unit inference) and C++ reader (arrays, locals, loops);
   `--import-check`
5. **#23** `feat/drawing` — pen, point editing, shape operations; palette
   orientation fix

Issues by milestone: M1 (refactor leftovers #9–#11), M2 Editor quirks (#7, #8,
#12, #13), M3 Drawing tools (#18–#21, closed by #22/#23). Peet's own UI quirks
go into M2 as new issues.

`--import-check <svg|cpp|folder> [pngdir]` is the tool for import problems:
run it over the file (or a whole plugin folder) to see what comes in and what
is lost. Render the original with `qlmanage -t -s 900 -o <dir> file.svg`
(WebKit) to compare.

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

The GUI cannot be tested headless. After UI changes, run `make app` (Peet
launches the bundle, not `.build/debug`) and ask him to check the affected
interactions by hand; a stale `PanelGenerator.app` looks like a broken feature.

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
  lock is stale; remove it. Cause, confirmed: Cowork sessions reach this
  folder through a Linux VM that can create files here but not delete them,
  so any git command run there leaves `index.lock` behind (one blocked
  commits for two weeks). From Cowork, run git only on the Mac (agent-runner),
  never through the VM shell.
- `_to_delete/` and `build/` are ignored scratch; don't commit from them.
