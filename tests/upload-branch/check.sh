#!/bin/sh
# bats upload names a stable version only on the main branch itself, as
# the Rust bats does (version::resolve_version); any other branch gets a
# dev1 version. It used to treat every branch starting with "main"
# (mainline, main-fix) as main.
# usage: tests/upload-branch/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/lib/src"
printf '[package]\nname = "branch"\nkind = "lib"\n' > "$TMP/lib/bats.toml"
printf '#pub fun f (): int\n\nimplement f () = 1\n' > "$TMP/lib/src/lib.bats"
printf 'build/\ndist/\ndocs/\n' > "$TMP/lib/.gitignore"
cd "$TMP/lib"
git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm t
upload_on() { # <branch> <dev1|stable>
  git checkout -q -B "$1"
  rm -rf "$TMP/repo" && mkdir "$TMP/repo"
  "$BATS" upload --repository "$TMP/repo" > "$TMP/up.log" 2>&1 || { echo "FAIL: upload on $1"; cat "$TMP/up.log"; exit 1; }
  arc=$(cd "$TMP/repo/branch" && ls *.bats)
  case "$2:$arc" in
    dev1:*dev1.bats) ;;
    stable:*dev1.bats) echo "FAIL: $1 uploaded $arc, want a stable version"; exit 1 ;;
    stable:*) ;;
    *) echo "FAIL: $1 uploaded $arc, want a dev1 version"; exit 1 ;;
  esac
}
upload_on main stable
upload_on mainline dev1
upload_on feature dev1
echo "upload-branch: ok"
