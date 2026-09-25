#!/usr/bin/env bash
# Behaviour-neutral check for refactors: build BASE (default: main) in a
# throwaway worktree, run every CLI verb with both binaries, and diff the
# outputs byte for byte.
#
#   Scripts/check-identical.sh [base-ref]
#
# Exit 0 and "IDENTICAL OUTPUTS" means the working tree renders, emits,
# compares and self-tests exactly like BASE. Any difference is listed.
set -u
BASE="${1:-main}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TMP="${TMPDIR:-/tmp}"; TMP="${TMP%/}"
WT="$TMP/pg-base-$$"
OUT="$TMP/pg-identical-$$"
trap 'git worktree remove --force "$WT" >/dev/null 2>&1; rm -rf "$OUT"' EXIT

git worktree add -q --detach "$WT" "$BASE" || exit 2
(cd "$WT" && swift build -q) || { echo "base $BASE does not build"; exit 2; }
swift build -q || { echo "working tree does not build"; exit 2; }

run() {  # $1 = label, $2 = binary
  local d="$OUT/$1"; mkdir -p "$d"
  "$2" --selftest "$d/selftest" > "$d/selftest.txt" 2>&1
  for doc in Panels/*.panelgen; do
    n=$(basename "$doc" .panelgen)
    "$2" --emit "$doc" "$d/emit-$n" --theme both > "$d/emit-$n.txt" 2>&1
  done
  "$2" --compare Panels/GTO.panelgen Panels/GTO.svg > "$d/compare.txt" 2>&1
  "$2" --icon Panels/GTO.panelgen "$d/icon.png" 256 > /dev/null 2>&1
  "$2" --grid Panels/GTO.panelgen "$d/grid.png" > "$d/grid.txt" 2>&1
  # Output paths appear in the logs; normalise them.
  sed -i '' "s|$d|OUT|g" "$d"/*.txt
}
run base "$WT/.build/debug/PanelGenerator"
run head "$ROOT/.build/debug/PanelGenerator"

if diff -rq "$OUT/base" "$OUT/head"; then
  echo "IDENTICAL OUTPUTS (vs $BASE)"
else
  exit 1
fi
