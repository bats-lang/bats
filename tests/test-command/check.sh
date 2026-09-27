#!/bin/sh
# bats test runs the tests of the $UNITTEST.run blocks of src/: each
# "fn <name> (): bool" is run, with Rust's PASS/FAIL lines, and a failure
# fails the command. --filter selects by substring; with no test
# selected it says "no tests found". The Rust bats's runner called the
# tests from an entry that could not see them (they were not in the
# .sats), so it never ran one.
# usage: tests/test-command/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
d=$TMP/p; mkdir -p "$d/src/bin"
printf '[package]\nname = "tc"\nkind = "lib"\n' > "$d/bats.toml"
cat > "$d/src/lib.bats" <<'B'
#include "share/atspre_staload.hats"

#pub fn double (x: int): int

implement double (x) = x + x

$UNITTEST.run begin
fn test_double (): bool = double(2) = 4
(* a test may use a let, and helpers that are not tests *)
fn helper (x: int): int = x * 3
fn test_helper (): bool = let
  val y = helper(double(1))
in y = 6 end
end
B
cat > "$d/src/extra.bats" <<'B'
#include "share/atspre_staload.hats"

$UNITTEST.run begin
fn test_wrong (): bool = 1 + 1 = 3
end
B
expect() { # <file> <text>
  grep -qF -- "$2" "$1" || { echo "FAIL: no \"$2\" in:"; cat "$1"; exit 1; }
}
# one failing test fails the run
if (cd "$d" && "$BATS" test) > "$d/out" 2>&1; then echo "FAIL: a failing test passed"; exit 1; fi
expect "$d/out" "running 3 native test(s)"
expect "$d/out" "  PASS test_double"
expect "$d/out" "  PASS test_helper"
expect "$d/out" "  FAIL test_wrong"
expect "$d/out" "error: native test failed"
# --filter
(cd "$d" && "$BATS" test --filter double) > "$d/out" 2>&1 || { echo "FAIL: --filter double"; cat "$d/out"; exit 1; }
expect "$d/out" "running 1 native test(s)"
expect "$d/out" "all tests passed"
if grep -q "test_wrong" "$d/out"; then echo "FAIL: --filter ran test_wrong"; exit 1; fi
(cd "$d" && "$BATS" test --filter nothing) > "$d/out" 2>&1
expect "$d/out" "no tests found"
# tests in a binary cannot be linked into the runner: an error, not a skip
printf '#include "share/atspre_staload.hats"\n$UNITTEST.run begin\nfn test_b (): bool = true\nend\nimplement main0 () = ()\n' > "$d/src/bin/b.bats"
if (cd "$d" && "$BATS" test --filter double) > "$d/out" 2>&1; then echo "FAIL: tests in src/bin passed"; exit 1; fi
expect "$d/out" "cannot run: move them to a module of src/"
echo "test-command: ok"
