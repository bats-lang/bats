#!/bin/sh
# A binary whose src/ has 260 modules builds and runs, as with the Rust
# bats: every module is preprocessed, compiled, dynloaded and linked.
# Directory walks used to stop after 100 or 200 entries (fuel), and
# process spawn passed only the first 255 arguments, so the link lost
# modules.
# usage: tests/many-modules/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/src/bin"
cd "$TMP/p"
printf '[package]\nname = "many"\nkind = "bin"\n' > bats.toml
i=1
while [ $i -le 260 ]; do
  printf '#pub fun f%d (): int\n\nimplement f%d () = %d\n' $i $i $i > src/m$i.bats
  i=$((i + 1))
done
printf '#include "share/atspre_staload.hats"\n\nstaload "m260.sats"\nstaload "m9.sats"\n\nimplement main0 () = println! (f260 () + f9 ())\n' > src/bin/many.bats
"$BATS" build --only debug --only native > out 2> err || { echo "FAIL: build"; tail -5 err; exit 1; }
[ "$(./dist/debug/many)" = "269" ] || { echo "FAIL: output"; ./dist/debug/many; exit 1; }
echo "many-modules: ok"
