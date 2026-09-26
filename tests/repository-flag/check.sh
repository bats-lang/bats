#!/bin/sh
# --repository applies to the invocation that names it, and to no later
# one. It used to be kept in /tmp/_bpoc_repo.txt, so a later `bats
# upload` without the flag uploaded into the previous repository.
# usage: tests/repository-flag/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo" "$TMP/lib/src"
printf '[package]\nname = "repoflag"\nkind = "lib"\n' > "$TMP/lib/bats.toml"
printf '#pub fun f (): int\n\nimplement f () = 1\n' > "$TMP/lib/src/lib.bats"
printf 'build/\ndist/\ndocs/\n' > "$TMP/lib/.gitignore"
cd "$TMP/lib"
git init -q . && git add -A && git -c user.name=t -c user.email=t@t commit -qm t
"$BATS" upload --repository "$TMP/repo" > "$TMP/up1.log" 2>&1 || { echo "FAIL: first upload"; cat "$TMP/up1.log"; exit 1; }
n1=$(ls "$TMP/repo/repoflag" | wc -l)
"$BATS" upload > "$TMP/up2.log" 2>&1 || true
grep -q -- "requires --repository" "$TMP/up2.log" || {
  echo "FAIL: upload without --repository did not ask for it"; cat "$TMP/up2.log"; exit 1; }
n2=$(ls "$TMP/repo/repoflag" | wc -l)
[ "$n1" = "$n2" ] || { echo "FAIL: upload without --repository wrote into the previous repository"; exit 1; }
echo "repository-flag: ok"
