#!/bin/sh
# `bats lock` must resolve the dependencies of namespaced packages
# (bats_modules/NS/PKG/bats.toml), not just top-level ones.
# usage: tests/lock-namespace/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
REPO=$2
cd "$(dirname "$0")"
rm -rf bats_modules bats.lock
"$BATS" lock --repository "$REPO"
for dep in wasm.bats-packages.dev/bridge result promise; do
  grep -q "^$dep " bats.lock || { echo "FAIL: $dep missing from bats.lock"; cat bats.lock; exit 1; }
done
rm -rf bats_modules bats.lock
echo "lock-namespace: ok"
