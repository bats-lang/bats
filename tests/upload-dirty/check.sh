#!/bin/sh
# bats upload refuses a working tree with uncommitted or untracked files,
# as the Rust bats does (version::resolve_version), and writes nothing.
# It used to package whatever was on disk under the last commit's version.
# usage: tests/upload-dirty/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo" "$TMP/lib/src"
printf '[package]\nname = "dirty"\nkind = "lib"\n' > "$TMP/lib/bats.toml"
printf '#pub fun f (): int\n\nimplement f () = 1\n' > "$TMP/lib/src/lib.bats"
printf 'build/\ndist/\ndocs/\n' > "$TMP/lib/.gitignore"
cd "$TMP/lib"
git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm t
refused() { # <what>
  if "$BATS" upload --repository "$TMP/repo" > "$TMP/up.log" 2>&1; then
    echo "FAIL: uploaded with $1"; exit 1
  fi
  grep -qx 'error: working tree is dirty (commit or stash changes before upload)' "$TMP/up.log" || {
    echo "FAIL: $1: wrong message"; cat "$TMP/up.log"; exit 1; }
  [ ! -d "$TMP/repo/dirty" ] || { echo "FAIL: $1: wrote into the repository"; exit 1; }
}
printf '\n' >> src/lib.bats
refused "a modified file"
git checkout -q src/lib.bats
touch src/extra.bats
refused "an untracked file"
rm src/extra.bats
"$BATS" upload --repository "$TMP/repo" > "$TMP/up.log" 2>&1 || { echo "FAIL: clean upload"; cat "$TMP/up.log"; exit 1; }
echo "upload-dirty: ok"
