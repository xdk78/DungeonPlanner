#!/usr/bin/env bash
# Copies a pinned wow-ui-harness into this repository (vendored, so CI and the tests need no second checkout):
#   tests/vendor/wow-ui-harness/   the offline mock, layout, dump, lint and runner (lua/wowui/), LICENSE, VERSION
#   Libs/LibUIShots-1.0/           the in-game screenshot library (/dp shots)
# Usage, from the repository root:
#   tools/sync_harness.sh <harness checkout> [git ref, default HEAD]
# Then: lua tests/run.lua, lua tests/ui_dump.lua --out <dir>, review `git diff --stat`, commit.
# The harness's Python command line is not copied: run it from the harness checkout (AGENTS.md, "Seeing the UI").
set -euo pipefail

src="${1:?usage: tools/sync_harness.sh <harness checkout> [git ref]}"
ref="${2:-HEAD}"
[ -f DungeonPlanner.toc ] || { echo "run from the repository root" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git -C "$src" archive "$ref" lua lib LICENSE VERSION | tar -x -C "$work"
commit="$(git -C "$src" rev-parse "$ref")"
version="$(tr -d '\r\n' < "$work/VERSION")"

dest=tests/vendor/wow-ui-harness
rm -rf "$dest"
mkdir -p "$dest"
cp -r "$work/lua" "$dest/lua"
cp "$work/LICENSE" "$dest/LICENSE"
printf 'wow-ui-harness %s\ncommit %s\n' "$version" "$commit" > "$dest/VERSION"

rm -rf Libs/LibUIShots-1.0
cp -r "$work/lib/LibUIShots-1.0" Libs/LibUIShots-1.0

echo "wow-ui-harness $version ($commit) copied to $dest and Libs/LibUIShots-1.0"
