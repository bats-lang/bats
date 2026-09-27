#!/bin/sh
# A nullary constructor of a datatype that also has constructors with
# fields is a small integer, not a pointer; a case that tests it against
# a constructor with fields first must not read through it. ATS's
# ATSCKpat_con1 checks that the value is a pointer (at least
# ATS_DATACONMAX) before reading its tag; the wasm prelude's did not, so
# in wasm it read the tag at a low address (0 there), took the nullary
# value for the constructor whose tag is 0, and read its fields.
# usage: tests/wasm-prelude-con1/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
d=$TMP/p; mkdir -p "$d/src"
printf '[package]\nname = "wc"\nkind = "lib"\n' > "$d/bats.toml"
cat > "$d/src/lib.bats" <<'B'
#include "share/atspre_staload.hats"

#pub datavtype shape =
  | Circle of (int)
  | Rect of (int, int)
  | Empty of ()

#pub fn is_empty (s: shape): bool

implement is_empty (s) =
  case+ s of
  | ~Circle(_) => false
  | ~Rect(_, _) => false
  | ~Empty() => true

$UNITTEST.run(native, wasm) begin
fn test_empty (): bool = is_empty(Empty())
fn test_circle (): bool = ~is_empty(Circle(1))
fn test_rect (): bool = ~is_empty(Rect(1, 2))
end
B
(cd "$d" && "$BATS" test) > "$d/out" 2>&1 || { echo "FAIL: bats test"; cat "$d/out"; exit 1; }
grep -qF "all tests passed" "$d/out" || { echo "FAIL:"; cat "$d/out"; exit 1; }
echo "wasm-prelude-con1: ok"
