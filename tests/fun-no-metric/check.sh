#!/bin/sh
# A fun without a termination metric is unsafe and must be rejected,
# even when its quantifier contains "==".
# usage: tests/fun-no-metric/check.sh <bats-binary>
set -u
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Run in a copy, so nothing the commands write lands in the checkout
cp -R "$HERE/bats.toml" "$HERE/src" "$TMP/"
cd "$TMP"
rm -rf build dist
if "$BATS" check > "$TMP/check.log" 2>&1; then
  echo "FAIL: fun without a metric was accepted"; exit 1
fi
if ! grep -q 'unsafe construct' "$TMP/check.log"; then
  echo "FAIL: rejected, but not as an unsafe construct"; grep error "$TMP/check.log" | head -3; exit 1
fi
rm -rf build dist
echo "fun-no-metric: ok"
