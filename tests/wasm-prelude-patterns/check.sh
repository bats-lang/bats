#!/bin/sh
# A wasm binary whose case matches an int, bool or char literal (as css's
# unit and separator tables do) must not import ATSCKpat_int,
# ATSCKpat_bool or ATSCKpat_char: patsopt emits them as macros from
# ATS's pats_ccomp_instrset.h, which the wasm prelude lacked, so the C
# compiler took each for an undeclared function the host must provide,
# and the binary failed to instantiate.
# usage: tests/wasm-prelude-patterns/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/src/bin"
printf '[package]\nname = "wa"\nkind = "bin"\n' > "$TMP/p/bats.toml"
cat > "$TMP/p/src/bin/web.bats" <<'BATS'
#target wasm binary

#include "share/atspre_staload.hats"

fn of_int (i: int): int = case+ i of | 0 => 10 | 1 => 20 | _ => 30

fn of_bool (b: bool): int = case+ b of | true => 1 | false => 0

fn of_char (c: char): int = case+ c of | 'a' => 1 | _ => 0

implement main0 () = let
  val _ = of_int(1)
  val _ = of_bool(true)
  val _ = of_char('a')
in () end
BATS
cd "$TMP/p"
"$BATS" build --only debug > out 2> err || { echo "FAIL: build"; cat err out; exit 1; }
for f in ATSCKpat_int ATSCKpat_bool ATSCKpat_char; do
  if grep -q "$f" dist/debug/web.wasm; then
    echo "FAIL: web.wasm imports $f"; exit 1
  fi
done
echo "wasm-prelude-patterns: ok"
