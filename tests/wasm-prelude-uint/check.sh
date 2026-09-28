#!/bin/sh
# A wasm binary that works on uint (as sha256 does) or compares chars
# must not import the atspre_ uint or char operations: the host has no
# such functions, so the binary would not instantiate. The wasm prelude
# defines them as ATS's integer.cats and char.cats do.
# usage: tests/wasm-prelude-uint/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/src/bin"
printf '[package]\nname = "wu"\nkind = "bin"\n' > "$TMP/p/bats.toml"
cat > "$TMP/p/src/bin/web.bats" <<'BATS'
#target wasm binary

#include "share/atspre_staload.hats"

fn mix (x: uint, y: uint): uint =
  ((x + y) lxor (x << 3)) lor ((y >> 2) land (lnot x))

fn same (a: char, b: char): bool = a != b

implement main0 () = let
  val u = mix(g0int2uint(3), g0int2uint(5))
  val small = u < g0int2uint(9)
  val k: int = g0uint2int(u)
  val _ = (if small then k else 0): int
  val _ = same('a', 'b')
in () end
BATS
cd "$TMP/p"
"$BATS" build --only debug > out 2> err || { echo "FAIL: build"; cat err out; exit 1; }
for f in atspre_g0int2uint_int_uint atspre_g0uint2int_uint_int atspre_g0uint_add_uint \
         atspre_g0uint_lt_uint atspre_g0uint_lsl_uint atspre_g0uint_lsr_uint \
         atspre_g0uint_lor_uint atspre_g0uint_land_uint atspre_g0uint_lxor_uint \
         atspre_g0uint_lnot_uint atspre_neq_char0_char0 atspre_neq_char1_char1; do
  if grep -q "$f" dist/debug/web.wasm; then
    echo "FAIL: web.wasm imports $f"; exit 1
  fi
done
echo "wasm-prelude-uint: ok"
