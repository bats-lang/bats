#!/bin/sh
# A module's C is rebuilt when a .sats it staloads changes, not only its
# own .dats: m's #pub value changes from 1 to 2 and main, which only
# staloads m.sats, prints 2. It printed 1: main's .dats did not change, so
# its C (patsopt's inlining of the old m.sats) was taken for fresh. The
# Rust bats rewrites every .sats and .dats on every build, so its cache
# never keeps such C. A body-only change to m keeps main's C, since m.sats
# stays byte for byte the same and is not rewritten.
# usage: tests/sats-change/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
P=$TMP/p
mkdir -p "$P/src/bin"
printf '[package]\nname = "sc"\nkind = "bin"\n' > "$P/bats.toml"
m() { # <value> <body>
  printf '#include "share/atspre_staload.hats"\n\n#pub macdef kval = %s\n\n#pub fn f (): int\n\nimplement f () = %s\n' "$1" "$2" > "$P/src/m.bats"
}
m 1 0
printf '#include "share/atspre_staload.hats"\nstaload "m.sats"\nimplement main0 () = println! (kval)\n' > "$P/src/bin/sc.bats"
build() { # <expected output>
  (cd "$P" && "$BATS" build --only debug --only native) > "$TMP/out" 2>&1 || { echo "FAIL: build"; cat "$TMP/out"; exit 1; }
  got=$("$P/dist/debug/sc")
  [ "$got" = "$1" ] || { echo "FAIL: printed '$got', expected '$1'"; exit 1; }
}
build 1
S=$P/build/src/m.sats
C=$P/build/src/bin/sc_dats.c
touch -r "$S" "$TMP/s0"
# Freshness is by whole-second mtimes: each change is a second later
sleep 1
m 1 5
build 1
[ ! "$S" -nt "$TMP/s0" ] || { echo "FAIL: m.sats rewritten for a body-only change"; exit 1; }
touch -r "$C" "$TMP/c1"
sleep 1
m 2 5
build 2
[ "$C" -nt "$TMP/c1" ] || { echo "FAIL: main's C was not rebuilt"; exit 1; }
echo "sats-change: ok"
