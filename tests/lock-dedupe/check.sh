#!/bin/sh
# `bats lock` must write one line per package. json and toml share
# dependencies (arith, array, result, str); a pinned package used to be
# appended once per dependent and per pass. The second lock, run with
# bats_modules already present, is where that showed.
# usage: tests/lock-dedupe/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
REPO=$(cd "$2" && pwd)
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Run in a copy, so nothing the commands write lands in the checkout
cp -R "$HERE/bats.toml" "$HERE/src" "$TMP/"
cd "$TMP"
rm -rf bats_modules bats.lock
for run in 1 2; do
  "$BATS" lock --repository "$REPO" >/dev/null
  dups=$(cut -d' ' -f1 bats.lock | sort | uniq -d)
  [ -z "$dups" ] || { echo "FAIL: run $run: duplicate lock lines for: $dups"; cat bats.lock; exit 1; }
  for dep in json toml arith array result str; do
    grep -q "^$dep " bats.lock || { echo "FAIL: run $run: $dep missing from bats.lock"; cat bats.lock; exit 1; }
  done
done
rm -rf bats_modules bats.lock
echo "lock-dedupe: ok"
