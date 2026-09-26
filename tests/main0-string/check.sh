#!/bin/sh
# The entry point rename (implement main0 -> implement __BATS_main0)
# applies to code only. It used to rename the first "implement main0"
# in the emitted text, even inside a string literal or a comment, so
# this program failed to link. (The Rust bats has the same bug; this is
# an allowed divergence.)
# usage: tests/main0-string/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/p/src/bin"
printf '[package]\nname = "mainstr"\nkind = "bin"\n' > "$TMP/p/bats.toml"
cat > "$TMP/p/src/bin/mainstr.bats" <<'SRC'
val msg = "implement main0 () = ()"

(* implement main0 in a comment *)
// implement main0 in a line comment
implement main0 () = println! (msg)
SRC
cd "$TMP/p"
"$BATS" build --only debug --only native > build.log 2>&1 || { echo "FAIL: build"; grep -E "error" build.log | head -5; exit 1; }
out=$(./dist/debug/mainstr)
[ "$out" = "implement main0 () = ()" ] || { echo "FAIL: printed '$out'"; exit 1; }
echo "main0-string: ok"
