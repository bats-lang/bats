#!/bin/sh
# A module deleted from src/ is gone from the build: its files cached in
# build/src are removed before anything is compiled, so it is neither
# checked nor linked. They stayed, and the module list is read from
# build/src, so a deleted module's error was still reported (#219).
# probe.bats is built with the binary, then made wrong (it no longer
# type-checks): check fails on it. Deleted, check passes, a build
# links without it, and none of its files is left in build/src.
# usage: tests/module-deleted/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
P=$TMP/p
mkdir -p "$P/src/bin"
printf '[package]\nname = "md"\nkind = "bin"\n' > "$P/bats.toml"
printf '#include "share/atspre_staload.hats"\n\n#pub fn kept (): int\n\nimplement kept () = 7\n' > "$P/src/kept.bats"
printf '#include "share/atspre_staload.hats"\n\n#pub fn probe (): int\n\nimplement probe () = 1\n' > "$P/src/probe.bats"
printf '#include "share/atspre_staload.hats"\nstaload "kept.sats"\nimplement main0 () = println! (kept ())\n' > "$P/src/bin/md.bats"
(cd "$P" && "$BATS" build --only debug --only native) > "$TMP/out" 2>&1 || { echo "FAIL: first build"; cat "$TMP/out"; exit 1; }
ls "$P"/build/src/probe* > /dev/null 2>&1 || { echo "FAIL: probe was not built"; exit 1; }
printf '#include "share/atspre_staload.hats"\n\n#pub fn probe (): int\n\nimplement probe () = name_nowhere\n' > "$P/src/probe.bats"
if (cd "$P" && "$BATS" check) > "$TMP/out" 2>&1; then echo "FAIL: check passed with probe wrong"; exit 1; fi
rm "$P/src/probe.bats"
(cd "$P" && "$BATS" check) > "$TMP/out" 2>&1 || { echo "FAIL: check still fails with probe deleted"; cat "$TMP/out"; exit 1; }
(cd "$P" && "$BATS" build --only debug --only native) > "$TMP/out" 2>&1 || { echo "FAIL: build with probe deleted"; cat "$TMP/out"; exit 1; }
if ls "$P"/build/src/probe* > /dev/null 2>&1; then echo "FAIL: left in build/src:"; ls "$P"/build/src/probe*; exit 1; fi
if grep -q probe "$P"/build/src/bin/*.dats 2>/dev/null || grep -rq 'src/probe' "$P"/build/*.dats 2>/dev/null; then echo "FAIL: probe still linked"; exit 1; fi
got=$("$P/dist/debug/md")
[ "$got" = "7" ] || { echo "FAIL: printed '$got', expected 7"; exit 1; }
[ -f "$P/build/src/kept.sats" ] || { echo "FAIL: kept's files were removed"; exit 1; }
echo "module-deleted: ok"
