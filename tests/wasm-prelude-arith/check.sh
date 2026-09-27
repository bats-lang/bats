#!/bin/sh
# A wasm binary that uses nmod (as str's int_to_str does) or negates a
# bool (~b, as xml-tree does) must not import atspre_g1int_nmod_int or
# atspre_neg_bool0: the host provides no such functions, and bridge's
# JS used to stub every missing import to return 0, so nmod gave 0 and
# ~b gave false. The wasm prelude defines them as ATS's integer.cats
# and bool.cats do.
# usage: tests/wasm-prelude-arith/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/src/bin"
printf '[package]\nname = "wa"\nkind = "bin"\n' > "$TMP/p/bats.toml"
cat > "$TMP/p/src/bin/web.bats" <<'BATS'
#target wasm binary

#include "share/atspre_staload.hats"

fn digit {v:nat} (v: int v): int = nmod(v, 10) + ndiv(v, 10)

fn flip (b: bool): bool = ~b

implement main0 () = let
  val _ = digit(1234)
  val _ = flip(true)
in () end
BATS
cd "$TMP/p"
"$BATS" build --only debug > out 2> err || { echo "FAIL: build"; cat err out; exit 1; }
for f in atspre_g1int_nmod_int atspre_g0int_nmod_int atspre_neg_bool0 atspre_neg_bool; do
  if grep -q "$f" dist/debug/web.wasm; then
    echo "FAIL: web.wasm imports $f"; exit 1
  fi
done
echo "wasm-prelude-arith: ok"
