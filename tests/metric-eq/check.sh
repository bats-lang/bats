#!/bin/sh
# A fun with "==" in its quantifier before .<metric>. is safe: the lexer
# must see the metric and `bats check` must pass.
# usage: tests/metric-eq/check.sh <bats-binary>
set -u
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
cd "$(dirname "$0")"
rm -rf build dist
if ! "$BATS" check > /tmp/metric-eq.log 2>&1; then
  echo "FAIL: fun with == before its metric was rejected"; grep error /tmp/metric-eq.log | head -3
  exit 1
fi
rm -rf build dist
echo "metric-eq: ok"
