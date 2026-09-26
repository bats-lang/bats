#!/bin/sh
# bats check writes docs/ for a library as the Rust bats does (doc.rs):
# one <module>.md per src file with #pub declarations, each "### `sig`"
# followed by its /// comment, and an index.md listing the modules.
# expected/ is the Rust bats's output for this package.
# usage: tests/docs/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
HERE=$(cd "$(dirname "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cp -R "$HERE/bats.toml" "$HERE/src" "$TMP/"
cd "$TMP"
"$BATS" check > check.log 2>&1 || { echo "FAIL: check"; cat check.log; exit 1; }
grep -q "generated docs (2 module(s))" check.log || { echo "FAIL: no 'generated docs' line"; cat check.log; exit 1; }
diff -r "$HERE/expected" docs || { echo "FAIL: docs differ from the Rust bats's"; exit 1; }
echo "docs: ok"
