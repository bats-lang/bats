#!/bin/sh
# A module with tests may staload another module's .sats, also one with tests
# of its own (bats-lang/bats#633, keyword: test dispatch): each module's
# __bats_test is implemented under BATS_SELF, its own declaration. Unqualified,
# the name bound to the later of the two declarations, so the second module's
# implementation was helpers.sats's and the link failed with "multiple
# definition of ..._helpers_056_sats____bats_test".
# usage: tests/test-staload/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
. "$(dirname "$0")/../keep-on-fail.sh"
d=$TMP/p; mkdir -p "$d/src"
printf '[package]\nname = "ts"\nkind = "lib"\n' > "$d/bats.toml"
cat > "$d/src/helpers.bats" <<'B'
#include "share/atspre_staload.hats"

#pub fn double (x: int): int

implement double (x) = x + x

$UNITTEST.run begin
fn test_double (): bool = double(2) = 4
end
B
cat > "$d/src/other.bats" <<'B'
#include "share/atspre_staload.hats"
staload "./helpers.sats"

#pub fn quad (x: int): int

implement quad (x) = double(double(x))

$UNITTEST.run begin
fn test_quad (): bool = quad(2) = 8
end
B
expect() { # <file> <text>
  grep -qF -- "$2" "$1" || { echo "FAIL: no \"$2\" in:"; cat "$1"; exit 1; }
}
(cd "$d" && "$BATS" check) > "$d/out" 2>&1 || { echo "FAIL: check"; cat "$d/out"; exit 1; }
(cd "$d" && "$BATS" test) > "$d/out" 2>&1 || { echo "FAIL: test"; cat "$d/out"; exit 1; }
expect "$d/out" "running 2 native test(s)"
expect "$d/out" "  PASS test_double"
expect "$d/out" "  PASS test_quad"
expect "$d/out" "all tests passed"
echo "test-staload: ok"
