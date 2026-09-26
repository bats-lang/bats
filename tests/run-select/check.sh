#!/bin/sh
# bats run picks the binary as the Rust bats did: --bin names one of the
# built binaries; without --bin there must be exactly one. It used to
# run ./dist/<mode>/<package name>, whatever the binaries were called.
# usage: tests/run-select/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/two/src/bin" "$TMP/solo/src/bin"
printf '[package]\nname = "two"\nkind = "bin"\n' > "$TMP/two/bats.toml"
printf 'implement main0 () = ()\n' > "$TMP/two/src/bin/alpha.bats"
printf 'implement main0 () = exit_void (5)\n' > "$TMP/two/src/bin/beta.bats"
printf '[package]\nname = "solo"\nkind = "bin"\n' > "$TMP/solo/bats.toml"
printf 'implement main0 () = exit_void (6)\n' > "$TMP/solo/src/bin/other.bats"

expect() { # <dir> <want status> <want stderr text or ""> <args...>
  d=$1; want=$2; text=$3; shift 3
  rc=0; (cd "$TMP/$d" && "$BATS" run "$@") > "$TMP/out.log" 2> "$TMP/err.log" || rc=$?
  [ "$rc" = "$want" ] || { echo "FAIL: run $* in $d exited $rc, want $want"; cat "$TMP/out.log" "$TMP/err.log"; exit 1; }
  [ -z "$text" ] || grep -qF -- "$text" "$TMP/err.log" || {
    echo "FAIL: run $* in $d: stderr lacks: $text"; cat "$TMP/err.log"; exit 1; }
}
expect two 1 "error: multiple binaries available, specify one with --bin <name>: alpha, beta"
expect two 5 "" --bin beta
expect two 0 "" --bin alpha
expect two 1 "error: binary 'gamma' not found. Available: alpha, beta" --bin gamma
expect solo 6 ""
echo "run-select: ok"
