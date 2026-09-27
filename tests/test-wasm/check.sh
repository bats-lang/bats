#!/bin/sh
# bats test runs the tests of $UNITTEST.run blocks that target wasm in
# Node, after the native ones, as the Rust bats's run_wasm_tests did:
# "running N wasm test(s)", the PASS/FAIL lines, the counts, and a
# failure fails the command with "error: wasm test failed". A test of
# both targets runs in both. --only wasm runs the wasm tests alone.
# usage: tests/test-wasm/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
d=$TMP/p; mkdir -p "$d/src"
printf '[package]\nname = "tw"\nkind = "lib"\n' > "$d/bats.toml"
cat > "$d/src/lib.bats" <<'B'
#include "share/atspre_staload.hats"

#pub fn double (x: int): int

implement double (x) = x + x

$UNITTEST.run(native) begin
fn test_native (): bool = double(2) = 4
end

$UNITTEST.run(wasm) begin
fn test_wasm (): bool = double(3) = 6
end

$UNITTEST.run(native, wasm) begin
fn test_both (): bool = double(0) = 0
end
B
expect() { # <file> <text>
  grep -qF -- "$2" "$1" || { echo "FAIL: no \"$2\" in:"; cat "$1"; exit 1; }
}
(cd "$d" && "$BATS" test) > "$d/out" 2>&1 || { echo "FAIL: bats test"; cat "$d/out"; exit 1; }
expect "$d/out" "running 2 native test(s)"
expect "$d/out" "running 2 wasm test(s)"
expect "$d/out" "  PASS test_native"
expect "$d/out" "  PASS test_wasm"
expect "$d/out" "  PASS test_both"
expect "$d/out" "2 passed, 0 failed"
expect "$d/out" "all tests passed"
(cd "$d" && "$BATS" test --only wasm) > "$d/out" 2>&1 || { echo "FAIL: --only wasm"; cat "$d/out"; exit 1; }
expect "$d/out" "running 2 wasm test(s)"
if grep -q "native test" "$d/out"; then echo "FAIL: --only wasm ran native tests"; exit 1; fi
cat > "$d/src/extra.bats" <<'B'
#include "share/atspre_staload.hats"

$UNITTEST.run(wasm) begin
fn test_wrong (): bool = 1 + 1 = 3
end
B
if (cd "$d" && "$BATS" test --only wasm) > "$d/out" 2>&1; then echo "FAIL: a failing wasm test passed"; exit 1; fi
expect "$d/out" "  FAIL test_wrong"
expect "$d/out" "2 passed, 1 failed"
expect "$d/out" "error: wasm test failed"
echo "test-wasm: ok"
