#!/bin/sh
# A bats.toml that is not valid TOML is rejected before anything else
# reads it, with the toml crate's message: an unclosed or doubled table
# header, a key without =, an invalid key, a bare word as a value, an
# unterminated string, a bad escape, something after a value, a
# duplicate header or key. Arrays, inline tables, multi-line strings and
# [[arrays of tables]] stay valid. These files used to pass.
# expected.txt is the Rust bats' output for each case.
# usage: tests/toml-syntax-errors/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
n=0
for body in '[package\nname = "x"\n' '[package]\nname = "x\n' '[package]\nname = x\n' \
  '[package]\nname = "x"\nname = "y"\n' '[package]\nname "x"\n' '[package]]\nname = "a"\n' \
  '[package]\nname = "a" extra\n' '[package]\nname = "a"\n[package]\n' 'name\n' \
  '[package]\n= "a"\n' '[package]\nname = \n' '[]\n' '[package]\nname = "a\\q"\n' '[pack age]\n' \
  '[package]\nname = "a"\nv = [1, 2]\nt = { a = 1 }\nm = """x\ny"""\n' \
  '[package]\nname = "a"\n[dependencies]\narith = ""\narith = ">= 1"\n' 'x = 1\nx = 2\n[package]\nname = "a"\n' \
  '[package]\nname = "a"\n# c\n\n[[bin]]\nname = "x"\n' '[package]\nname = "a" # ok\nkind = "lib"   \n'; do
  n=$((n + 1)); d=$TMP/c$n
  mkdir -p "$d/src"
  printf "$body" > "$d/bats.toml"
  printf '#pub fn f (): int\n\nimplement f () = 1\n' > "$d/src/lib.bats"
  rc=0
  (cd "$d" && NO_COLOR=1 "$BATS" check) > /dev/null 2> "$d/err" || rc=$?
  { echo "=== $n rc=$rc"; cat "$d/err"; } >> "$TMP/got"
done
cmp -s "$TMP/got" "$HERE/expected.txt" || { echo "FAIL"; diff "$HERE/expected.txt" "$TMP/got"; exit 1; }
echo "toml-syntax-errors: ok"
