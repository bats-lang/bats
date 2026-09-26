#!/bin/sh
# bats clean removes build/, dist/ and docs/ and prints "cleaned N
# artifacts" to stderr, N being how many of them existed, as the Rust
# bats does (build::clean); --quiet prints nothing. It used to print
# "cleaned build/, dist/, and docs/" to stdout whatever was there.
# usage: tests/clean/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
mkdir -p build/src docs
"$BATS" clean > out.log 2> err.log
[ "$(cat err.log)" = "cleaned 2 artifacts" ] || { echo "FAIL: stderr is '$(cat err.log)'"; exit 1; }
[ ! -s out.log ] || { echo "FAIL: stdout is '$(cat out.log)'"; exit 1; }
[ ! -e build ] && [ ! -e docs ] || { echo "FAIL: build/ or docs/ left"; exit 1; }
"$BATS" clean 2> err.log
[ "$(cat err.log)" = "cleaned 0 artifacts" ] || { echo "FAIL: empty clean said '$(cat err.log)'"; exit 1; }
mkdir dist
"$BATS" --quiet clean > out.log 2>&1
[ ! -s out.log ] || { echo "FAIL: --quiet printed '$(cat out.log)'"; exit 1; }
[ ! -e dist ] || { echo "FAIL: dist/ left"; exit 1; }
echo "clean: ok"
