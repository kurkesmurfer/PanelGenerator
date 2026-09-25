#!/usr/bin/env python3
"""Flatten an SVG's <defs>-family content before PanelGenerator's importer sees it.

PanelGenerator's SVG importer skips <defs>, <clipPath>, <mask>, <marker>,
<pattern>, <filter> and <symbol> entirely rather than resolving what
references them (see PIPELINE.md) -- walking into one and drawing what's
inside would scatter reference-only content across the panel as if it were
real artwork. Most of the time that warning is noise: Illustrator and
Inkscape both routinely leave <defs> content in an exported SVG that nothing
in the visible drawing actually uses. This script removes exactly that, for
free and losslessly, via Inkscape's own CLI:

  1. Unlink every <use> / cloned <symbol> reference into real, standalone
     geometry (Inkscape action `object-unlink-clones`) -- turns a reused
     icon into an ordinary group of shapes the importer reads natively.
  2. Vacuum defs (`--vacuum-defs`) -- removes anything left in <defs> that
     step 1 didn't just orphan and nothing else in the file references
     either (an unused gradient, an unused clipPath, a symbol nothing still
     points at after step 1).

What's left after both passes is, by construction, something the visible
artwork genuinely depends on -- a clip, a mask, a gradient, a pattern, a
filter -- and flattening *that* is a real design decision (what replaces a
gradient? which shape does a clip actually trim?), not something safe to
automate generically. The script reports exactly what's left, by tag and id,
rather than guessing.

Usage:
    Scripts/flatten-svg.py in.svg [out.svg]
    Scripts/flatten-svg.py in.svg --in-place

With no output path, writes <name>-flat.svg next to the input rather than
overwriting it. Requires Inkscape (checked on $PATH, then the standard
/Applications/Inkscape.app location on macOS); tested against 1.4.
"""
import argparse
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SVG_NS = "http://www.w3.org/2000/svg"
SKIP_TAGS = {"defs", "clippath", "mask", "marker", "pattern", "filter", "symbol"}


def find_inkscape() -> str:
    found = shutil.which("inkscape")
    if found:
        return found
    mac_default = "/Applications/Inkscape.app/Contents/MacOS/inkscape"
    if Path(mac_default).exists():
        return mac_default
    sys.exit("flatten-svg: Inkscape not found on PATH or at " + mac_default
              + " -- install it, or point PATH at it, and try again.")


def run_inkscape(inkscape: str, args: list, cwd: Path):
    result = subprocess.run([inkscape] + args, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"flatten-svg: inkscape failed ({' '.join(args)}):\n{result.stderr}")


def local_tag(elem) -> str:
    """Element tag without its namespace, lowercased -- 'clipPath' -> 'clippath'."""
    t = elem.tag
    if "}" in t:
        t = t.split("}", 1)[1]
    return t.lower()


def strip_ns(tag: str) -> str:
    return tag.split("}", 1)[1] if "}" in tag else tag


def find_remaining(svg_path: Path):
    """Every *outermost* skip-family element in the file that still has real
    content, as (tag, id, [descendant tag names]) -- mirrors PanelGenerator's
    own importer, which skips a subtree at its first skip-tag ancestor and
    never looks inside it again. A <clipPath> nested inside a <defs> is
    reported once, as part of the <defs> entry, not a second time on its own.
    """
    tree = ET.parse(svg_path)
    root = tree.getroot()
    remaining = []

    def walk(elem, inside_skip: bool):
        tag = local_tag(elem)
        if not inside_skip and tag in SKIP_TAGS:
            descendants = [strip_ns(c.tag) for c in elem.iter() if c is not elem]
            if descendants:
                remaining.append((strip_ns(elem.tag), elem.get("id", "(no id)"), descendants))
            return   # don't descend further -- matches the importer's own skipDepth behaviour
        for child in elem:
            walk(child, inside_skip or tag in SKIP_TAGS)

    for child in root:
        walk(child, False)
    return remaining


ADVICE = {
    "clipPath": "genuinely clips something -- Boolean-intersect the clipped "
                "shape with the clip path's own outline (Inkscape: select "
                "both, Path > Intersection) to bake it into real geometry.",
    "mask": "genuinely masks something -- same idea as a clip, but a mask "
            "can vary opacity across itself, which a flat cutout can't "
            "reproduce; redraw the intended shape by hand if it needs more "
            "than a hard edge.",
    "linearGradient": "used as a fill -- PanelGenerator fills are solid; "
                       "pick a representative flat colour and set it directly.",
    "radialGradient": "used as a fill -- same as linearGradient above.",
    "pattern": "used as a fill -- redraw as real, individual shapes; there's "
               "no generic way to bake a repeating pattern into one path.",
    "filter": "applied to something -- filters (blur, glow, etc.) have no "
              "equivalent in PanelGenerator's flat-fill renderer; redraw the "
              "intended look directly or drop it.",
    "marker": "used on a path's vertices/ends -- redraw as real shapes at "
              "those points if the marker is meant to be visible artwork.",
    "symbol": "still referenced by something this pass didn't unlink -- "
              "check for a <use> this script's clone-unlink pass missed "
              "(e.g. one added by a filter or CSS, not a plain href).",
}


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("input", type=Path, help="source .svg")
    p.add_argument("output", type=Path, nargs="?", help="where to write the flattened .svg "
                    "(default: <name>-flat.svg next to the input)")
    p.add_argument("--in-place", action="store_true", help="overwrite the input instead of "
                    "writing a new file")
    args = p.parse_args()

    if not args.input.exists():
        sys.exit(f"flatten-svg: no such file: {args.input}")

    if args.in_place:
        out_path = args.input
    elif args.output:
        out_path = args.output
    else:
        out_path = args.input.with_name(args.input.stem + "-flat.svg")

    inkscape = find_inkscape()
    work_dir = args.input.resolve().parent

    step1 = args.input.resolve().parent / (args.input.stem + ".flatten-tmp1.svg")
    try:
        # Pass 1: turn every <use>/cloned <symbol> into real, standalone
        # geometry. Run first so pass 2's vacuum also sweeps up whatever
        # this orphans (a <symbol> nothing points at any more).
        run_inkscape(inkscape,
                     ["--actions=select-all;object-unlink-clones;"
                      f"export-filename:{step1.name};export-plain-svg;export-do",
                      args.input.resolve().name],
                     cwd=work_dir)
        # Pass 2: remove whatever's left in <defs> that nothing references.
        run_inkscape(inkscape,
                     ["--vacuum-defs", "--export-plain-svg",
                      f"--export-filename={out_path.resolve()}", step1.name],
                     cwd=work_dir)
    finally:
        step1.unlink(missing_ok=True)

    remaining = find_remaining(out_path)
    if not remaining:
        print(f"flatten-svg: {out_path} -- clean. Nothing left for PanelGenerator's "
              "importer to skip; every <defs>-family element was either unused or has "
              "now been unlinked into real geometry.")
        return

    print(f"flatten-svg: {out_path} -- {len(remaining)} element(s) still need manual "
          "attention (genuinely referenced by the visible artwork, so not safe to "
          "flatten automatically):\n")
    for tag, ident, descendants in remaining:
        distinct = sorted(set(descendants))
        print(f"  <{tag} id=\"{ident}\">  contains: {', '.join(distinct)}")
        # Advice per construct actually found inside -- a <defs> reported here
        # may hold more than one kind (a clipPath AND a gradient, say), so
        # print a note for every ADVICE-covered tag among its descendants,
        # not just one guess.
        notes = [ADVICE[d] for d in distinct if d in ADVICE]
        if tag in ADVICE and tag not in distinct:
            notes.insert(0, ADVICE[tag])
        for note in dict.fromkeys(notes):   # de-duplicate, keep order
            print(f"    -> {note}")
    print("\nEverything else in the file was flattened cleanly.")


if __name__ == "__main__":
    main()
