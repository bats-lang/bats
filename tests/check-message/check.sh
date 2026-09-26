#!/bin/sh
# A passing bats check prints "check passed (library)" or "check passed
# (binary)" to stderr, as the Rust bats does (build::check), and nothing
# with --quiet. It used to print "  process: check passed", "  exit
# code: 0" and "check passed" to stdout.
# usage: tests/check-message/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/l/src" "$TMP/b/src/bin"
printf '[package]\nname = "cml"\nkind = "lib"\n' > "$TMP/l/bats.toml"
printf '#pub fn f (): int\n\nimplement f () = 1\n' > "$TMP/l/src/lib.bats"
printf '[package]\nname = "cmb"\nkind = "bin"\n' > "$TMP/b/bats.toml"
printf 'implement main0 () = ()\n' > "$TMP/b/src/bin/cmb.bats"
expect() { # <dir> <kind>
  (cd "$TMP/$1" && "$BATS" check) > "$TMP/out" 2> "$TMP/err" || { echo "FAIL: check in $1"; cat "$TMP/out" "$TMP/err"; exit 1; }
  grep -qx "check passed ($2)" "$TMP/err" || { echo "FAIL: $1: stderr lacks 'check passed ($2)'"; cat "$TMP/err"; exit 1; }
  ! grep -q "check passed" "$TMP/out" || { echo "FAIL: $1: stdout has 'check passed'"; cat "$TMP/out"; exit 1; }
  (cd "$TMP/$1" && "$BATS" --quiet check) > "$TMP/out" 2>&1
  ! grep -q "check passed" "$TMP/out" || { echo "FAIL: $1: --quiet printed 'check passed'"; exit 1; }
}
expect l library
expect b binary
echo "check-message: ok"
