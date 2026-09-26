#!/bin/sh
# bats upload outside a git repository fails with the Rust bats' message
# (version::resolve_version) and writes nothing. It used to upload under
# a version made from an empty git log.
# usage: tests/upload-no-git/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Keep git from finding a repository above the scratch directory
GIT_CEILING_DIRECTORIES=$TMP
export GIT_CEILING_DIRECTORIES
mkdir -p "$TMP/repo" "$TMP/lib/src"
printf '[package]\nname = "nogit"\nkind = "lib"\n' > "$TMP/lib/bats.toml"
printf '#pub fun f (): int\n\nimplement f () = 1\n' > "$TMP/lib/src/lib.bats"
cd "$TMP/lib"
if "$BATS" upload --repository "$TMP/repo" > "$TMP/up.log" 2>&1; then
  echo "FAIL: uploaded outside a git repository"; exit 1
fi
grep -qx 'error: not a git repository (required for auto-versioning)' "$TMP/up.log" || {
  echo "FAIL: wrong message"; cat "$TMP/up.log"; exit 1; }
[ ! -d "$TMP/repo/nogit" ] || { echo "FAIL: wrote into the repository"; exit 1; }
echo "upload-no-git: ok"
