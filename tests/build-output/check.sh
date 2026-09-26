#!/bin/sh
# bats build reports each binary it builds as the Rust bats does, and
# nothing else: "built ./dist/<profile>/<name> (<profile>)" on stderr,
# silenced by --quiet; nothing on stdout.
# usage: tests/build-output/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/src/bin"
printf '[package]\nname = "bout"\nkind = "bin"\n' > "$TMP/p/bats.toml"
printf 'implement main0 () = println! ("hi")\n' > "$TMP/p/src/bin/bout.bats"
cd "$TMP/p"
"$BATS" build --only debug --only native > out 2> err || { echo "FAIL: build"; cat out err; exit 1; }
[ ! -s out ] || { echo "FAIL: stdout is not empty"; cat out; exit 1; }
[ "$(cat err)" = "built ./dist/debug/bout (debug)" ] || { echo "FAIL: stderr"; cat err; exit 1; }
rm -rf build dist
"$BATS" --quiet build --only release --only native > out 2> err || { echo "FAIL: quiet build"; cat out err; exit 1; }
[ ! -s out ] && [ ! -s err ] || { echo "FAIL: --quiet printed"; cat out err; exit 1; }
[ -x dist/release/bout ] || { echo "FAIL: no dist/release/bout"; exit 1; }
echo "build-output: ok"
