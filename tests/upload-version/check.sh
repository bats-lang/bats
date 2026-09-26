#!/bin/sh
# bats upload uses [package] version from bats.toml when it is set, as the
# Rust bats does (version::resolve_version), without consulting git: no
# repository or a dirty tree does not matter. It used to ignore the key
# and derive a version from git.
# usage: tests/upload-version/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
GIT_CEILING_DIRECTORIES=$TMP
export GIT_CEILING_DIRECTORIES
mkdir -p "$TMP/repo" "$TMP/lib/src"
printf '[package]\nname = "explicit"\nversion = "1.2.3"\nkind = "lib"\n' > "$TMP/lib/bats.toml"
printf '#pub fun f (): int\n\nimplement f () = 1\n' > "$TMP/lib/src/lib.bats"
cd "$TMP/lib"
"$BATS" upload --repository "$TMP/repo" > "$TMP/up.log" 2>&1 || { echo "FAIL: upload"; cat "$TMP/up.log"; exit 1; }
[ -f "$TMP/repo/explicit/explicit_1.2.3.bats" ] || { echo "FAIL: no explicit_1.2.3.bats"; ls -R "$TMP/repo"; exit 1; }
echo "upload-version: ok"
