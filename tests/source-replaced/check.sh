#!/bin/sh
# A module is emitted again when its source changes, whatever the new
# file's mtime: m.bats is replaced by one with other contents and an older
# mtime (as bats lock leaves a dependency's files: they keep their
# archive's mtimes), and the binary prints m's new value. It printed the
# old one: the .dats, newer than the new file, was taken for fresh. The
# Rust bats rewrites every .sats and .dats on every build.
# usage: tests/source-replaced/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
P=$TMP/p
mkdir -p "$P/src/bin"
printf '[package]\nname = "sr"\nkind = "bin"\n' > "$P/bats.toml"
m() { # <value>
  printf '#include "share/atspre_staload.hats"\n\n#pub fn f (): int\n\nimplement f () = %s\n' "$1" > "$P/src/m.bats"
}
m 1
printf '#include "share/atspre_staload.hats"\nstaload "m.sats"\nimplement main0 () = println! (f ())\n' > "$P/src/bin/sr.bats"
build() { # <expected output>
  (cd "$P" && "$BATS" build --only debug --only native) > "$TMP/out" 2>&1 || { echo "FAIL: build"; cat "$TMP/out"; exit 1; }
  got=$("$P/dist/debug/sr")
  [ "$got" = "$1" ] || { echo "FAIL: printed '$got', expected '$1'"; exit 1; }
}
build 1
m 2
touch -t 200001010000 "$P/src/m.bats"
build 2
# Unchanged sources are not emitted again
D=$P/build/src/m.dats
touch -r "$D" "$TMP/d0"
sleep 1
build 2
[ ! "$D" -nt "$TMP/d0" ] || { echo "FAIL: m.dats emitted again with m.bats unchanged"; exit 1; }
echo "source-replaced: ok"
