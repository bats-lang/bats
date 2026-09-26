#!/bin/sh
# --bin applies to the invocation that names it, and to no later one. It
# used to be kept in /tmp/_bpoc_bin.txt, so after `bats run --bin x` in
# one project, `bats run` in another still ran ./dist/debug/x.
# Binaries report through their exit status (bats run says "run failed"
# for a non-zero one).
# usage: tests/run-bin/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/a/src/bin" "$TMP/b/src/bin"
printf '[package]\nname = "a"\nkind = "bin"\n' > "$TMP/a/bats.toml"
printf 'implement main0 () = ()\n' > "$TMP/a/src/bin/a.bats"
printf 'implement main0 () = exit_void (3)\n' > "$TMP/a/src/bin/x.bats"
printf '[package]\nname = "b"\nkind = "bin"\n' > "$TMP/b/bats.toml"
printf 'implement main0 () = ()\n' > "$TMP/b/src/bin/b.bats"
(cd "$TMP/a" && "$BATS" run --bin x) > "$TMP/r1.log" 2>&1 || true
grep -q "run failed" "$TMP/r1.log" || { echo "FAIL: run --bin x did not run x"; cat "$TMP/r1.log"; exit 1; }
(cd "$TMP/b" && "$BATS" run) > "$TMP/r2.log" 2>&1 || true
if grep -q "run failed" "$TMP/r2.log"; then
  echo "FAIL: run in another project still used --bin x"; cat "$TMP/r2.log"; exit 1
fi
echo "run-bin: ok"
