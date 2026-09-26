#!/bin/sh
# $X.member is accepted when X is bound by ATS's staload X = "...", as
# well as by #use ... as X; packages staload bridge modules this way. The
# Rust bats knew only #use aliases and reported "unknown alias" (an
# allowed divergence). An alias neither binds is still rejected.
# usage: tests/staload-alias/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/src"
printf '[package]\nname = "stl"\nkind = "lib"\n' > "$TMP/p/bats.toml"
cat > "$TMP/p/src/lib.bats" <<'SRC'
#include "share/atspre_staload.hats"
staload INT = "prelude/SATS/integer.sats"

#pub fn neg1 (): int

implement neg1 () = $INT.g0int_neg_int(1)
SRC
cd "$TMP/p"
"$BATS" check > log 2>&1 || { echo "FAIL: staload alias rejected"; cat log; exit 1; }
printf '#pub fn two (): int\n\nimplement two () = $NOPE.two\n' >> src/lib.bats
if "$BATS" check > log 2>&1; then echo "FAIL: unknown alias accepted"; exit 1; fi
grep -q "unknown alias 'NOPE' in qualified access" log || { echo "FAIL: message"; cat log; exit 1; }
echo "staload-alias: ok"
