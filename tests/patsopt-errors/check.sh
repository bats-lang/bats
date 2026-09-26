#!/bin/sh
# A type error stops check and build at the first failing file with
# Rust's report on stderr: "error: patsopt error:", then patsopt's lines
# with .dats/.sats read as .bats, build/ dropped and line numbers moved
# back over the prelude (build::remap_errors). It used to print patsopt's
# raw lines on stdout, then "patsopt failed for ...", clang and link
# errors, and the other profile's build. The expected files are the Rust
# bats' output, with the package's directory as X.
# usage: tests/patsopt-errors/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
case_() { # <name> <command>
  p=$TMP/$1
  rc=0
  (cd "$p" && NO_COLOR=1 "$BATS" $2) > "$TMP/out" 2> "$TMP/err" || rc=$?
  [ "$rc" = 1 ] || { echo "FAIL: $1: rc $rc"; cat "$TMP/err"; exit 1; }
  [ ! -s "$TMP/out" ] || { echo "FAIL: $1: stdout"; cat "$TMP/out"; exit 1; }
  sed "s|$p|X|g" "$TMP/err" > "$TMP/err.x"
  cmp -s "$TMP/err.x" "$HERE/$1.txt" || { echo "FAIL: $1"; diff "$HERE/$1.txt" "$TMP/err.x"; exit 1; }
}
mkdir -p "$TMP/lib/src" "$TMP/bin/src/bin" "$TMP/dep/src" "$TMP/dep/bats_modules/dq/src"
printf '[package]\nname = "po"\nkind = "lib"\n' > "$TMP/lib/bats.toml"
printf '#include "share/atspre_staload.hats"\n\nval x: int = "s"\n' > "$TMP/lib/src/lib.bats"
printf '[package]\nname = "po"\nkind = "bin"\n' > "$TMP/bin/bats.toml"
printf '#include "share/atspre_staload.hats"\n\nval x: int = "s"\nimplement main0 () = ()\n' > "$TMP/bin/src/bin/po.bats"
printf '[package]\nname = "po"\nkind = "lib"\n' > "$TMP/dep/bats.toml"
printf '[package]\nname = "dq"\nkind = "lib"\n' > "$TMP/dep/bats_modules/dq/bats.toml"
printf '#pub fn one (): int\n\nimplement one () = 1\n' > "$TMP/dep/bats_modules/dq/src/lib.bats"
printf '#include "share/atspre_staload.hats"\n#use dq as D\n\nval x: int = "s"\n' > "$TMP/dep/src/lib.bats"
case_ lib check
case_ bin build
[ ! -e "$TMP/bin/dist/release" ] || [ -z "$(ls "$TMP/bin/dist/release")" ] || { echo "FAIL: bin: built release after the error"; exit 1; }
case_ dep check
echo "patsopt-errors: ok"
