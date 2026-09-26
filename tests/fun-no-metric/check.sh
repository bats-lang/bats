#!/bin/sh
# A fun without a termination metric is unsafe and must be rejected,
# even when its quantifier contains "==".
# usage: tests/fun-no-metric/check.sh <bats-binary>
set -u
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
cd "$(dirname "$0")"
rm -rf build dist
if "$BATS" check > /tmp/fun-no-metric.log 2>&1; then
  echo "FAIL: fun without a metric was accepted"; exit 1
fi
if ! grep -q 'unsafe construct' /tmp/fun-no-metric.log; then
  echo "FAIL: rejected, but not as an unsafe construct"; grep error /tmp/fun-no-metric.log | head -3; exit 1
fi
rm -rf build dist
echo "fun-no-metric: ok"
