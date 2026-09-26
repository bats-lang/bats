#!/bin/sh
# A fun with "==" in its quantifier before .<metric>. is safe: the lexer
# must see the metric and `bats check` must pass.
# usage: tests/metric-eq/check.sh <bats-binary>
set -u
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Run in a copy, so nothing the commands write lands in the checkout
cp -R "$HERE/bats.toml" "$HERE/src" "$TMP/"
cd "$TMP"
rm -rf build dist
if ! "$BATS" check > "$TMP/check.log" 2>&1; then
  echo "FAIL: fun with == before its metric was rejected"; grep error "$TMP/check.log" | head -3
  exit 1
fi
rm -rf build dist
echo "metric-eq: ok"
