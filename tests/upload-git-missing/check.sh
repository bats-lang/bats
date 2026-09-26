#!/bin/sh
# bats upload with no git on PATH fails with the Rust bats' message
# (version::resolve_version: "git not found: <OS error>") and writes
# nothing. It used to report "not a git repository".
# usage: tests/upload-git-missing/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo" "$TMP/lib/src" "$TMP/empty"
printf '[package]\nname = "nogitbin"\nkind = "lib"\n' > "$TMP/lib/bats.toml"
printf '#pub fun f (): int\n\nimplement f () = 1\n' > "$TMP/lib/src/lib.bats"
cd "$TMP/lib"
if PATH="$TMP/empty" "$BATS" upload --repository "$TMP/repo" > "$TMP/up.log" 2>&1; then
  echo "FAIL: uploaded without git"; exit 1
fi
grep -qx 'error: git not found: No such file or directory (os error 2)' "$TMP/up.log" || {
  echo "FAIL: wrong message"; cat "$TMP/up.log"; exit 1; }
[ ! -d "$TMP/repo/nogitbin" ] || { echo "FAIL: wrote into the repository"; exit 1; }
echo "upload-git-missing: ok"
