#!/bin/sh
# `bats check` must exit non-zero when type-checking fails, so CI and
# scripts can rely on the exit status.
# usage: tests/check-fails/check.sh <bats-binary>
set -u
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Run in a copy, so nothing the commands write lands in the checkout
cp -R "$HERE/bats.toml" "$HERE/src" "$TMP/"
cd "$TMP"
rm -rf build dist
if "$BATS" check >/dev/null 2>&1; then
  echo "FAIL: bats check exited 0 on an ill-typed package"
  exit 1
fi
rm -rf build dist
echo "check-fails: ok"
