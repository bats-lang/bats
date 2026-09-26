#!/bin/sh
# `bats check` on a library must type-check every src module, not just
# lib.bats: a type error in src/other.bats must fail the check, and the
# same module without the error must pass.
# usage: tests/lib-module-error/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
REPO=$(cd "$2" && pwd)
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Run in a copy, so nothing the commands write lands in the checkout
cp -R "$HERE/bats.toml" "$HERE/src" "$TMP/"
cd "$TMP"
cleanup() { rm -rf build bats_modules bats.lock docs src/other.bats; }
cleanup
printf '#pub fun g (): int\n\nimplement g () = "not an int"\n' > src/other.bats
if "$BATS" check --repository "$REPO" > check.log 2>&1; then
  echo "FAIL: type error in src/other.bats passed check"; cat check.log; rm -f check.log; cleanup; exit 1
fi
grep -q "^/.*/src/other.bats: .*(line=3, " check.log || {
  echo "FAIL: check failed without naming src/other.bats"; cat check.log; rm -f check.log; cleanup; exit 1; }
printf '#pub fun g (): int\n\nimplement g () = 1\n' > src/other.bats
rm -rf build
"$BATS" check --repository "$REPO" > check.log 2>&1 || {
  echo "FAIL: a well-typed src/other.bats failed check"; cat check.log; rm -f check.log; cleanup; exit 1; }
rm -f check.log; cleanup
echo "lib-module-error: ok"
