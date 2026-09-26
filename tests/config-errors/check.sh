#!/bin/sh
# check, build and the rest read bats.toml as the Rust bats's
# config::load does (serde into Package): the first [package] field of
# the wrong type in the file's order, else a missing [package], else a
# missing name, reported as the toml crate reports it. These files used
# to pass (a missing name, a name = 3). expected.txt is the Rust bats'
# output for each case.
# usage: tests/config-errors/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
n=0
for body in '[package]\nkind = "lib"\n' '# c\n\n[package]\nkind = "bin"\nversion = "1"\n' \
  '[dependencies]\n' '' 'x = 1\n' '[package]\nname = 3\n' '[package]\nname = "a"\nkind = 5\n' \
  '[package] # hi\nkind = "lib"\n[dependencies]\n' '# c\n[dependencies]\n' \
  'x = 1\ny = 22\n[dependencies]\n' '# c\nx = 1\n' '\n\nx = 1\n' '[package]\nname = true\n' \
  '[package]\nname = ["a"]\n' '[package]\nname = {a = 1}\n' '[package]\nname = 1.5\n' \
  '  [package]  \nkind = "lib"\n' '[package]\nname = "a"\nunsafe = "yes"\n' \
  '[package]\nname = "a"\nunsafe = 1\n' '[package]\nname = x\n' \
  "[package]\nname = 'lit'\nkind = 'lib'\n" '[package]\nname = "a"\nunsafe = true # c\n' \
  '[package]\nkind = 3\nname = true\n' '[package]\nname = -1_000\n' '[package]\nname = 1_000\n' \
  '[package]\nname = +7\n'; do
  n=$((n + 1)); d=$TMP/c$n
  mkdir -p "$d/src"
  printf "$body" > "$d/bats.toml"
  printf '#pub fn f (): int\n\nimplement f () = 1\n' > "$d/src/lib.bats"
  rc=0
  (cd "$d" && NO_COLOR=1 "$BATS" check) > /dev/null 2> "$d/err" || rc=$?
  { echo "=== $n rc=$rc"; cat "$d/err"; } >> "$TMP/got"
done
cmp -s "$TMP/got" "$HERE/expected.txt" || { echo "FAIL"; diff "$HERE/expected.txt" "$TMP/got"; exit 1; }
echo "config-errors: ok"
