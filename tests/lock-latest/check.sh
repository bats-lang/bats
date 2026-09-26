#!/bin/sh
# `bats lock` resolves each dependency to the latest version in the
# repository, as the Rust bats does (lock::resolve_all). It used to keep
# the version already in bats.lock whenever bats_modules/<dep> existed,
# so a relock never picked up a new release.
# usage: tests/lock-latest/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/repo" "$TMP/dep/src" "$TMP/app/src"
printf '[package]\nname = "latestdep"\nkind = "lib"\n' > "$TMP/dep/bats.toml"
printf '#pub fun f (): int\n\nimplement f () = 1\n' > "$TMP/dep/src/lib.bats"
printf 'build/\ndist/\ndocs/\n' > "$TMP/dep/.gitignore"
printf '[package]\nname = "latestapp"\nkind = "lib"\n\n[dependencies]\n"latestdep" = ""\n' > "$TMP/app/bats.toml"
printf '#pub fun g (): int\n\nimplement g () = 2\n' > "$TMP/app/src/lib.bats"
publish() { # <commit date>: commit dep and upload it
  (cd "$TMP/dep" && git add -A &&
   GIT_COMMITTER_DATE="$1" git -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$1" &&
   "$BATS" upload --repository "$TMP/repo" > "$TMP/up.log" 2>&1) || { echo "FAIL: upload"; cat "$TMP/up.log"; exit 1; }
}
(cd "$TMP/dep" && git init -q -b main .)
publish "2026-01-01T00:00:10Z"
cd "$TMP/app"
"$BATS" lock --repository "$TMP/repo" > /dev/null 2>&1
grep -q '^latestdep 2026.1.1.10 ' bats.lock || { echo "FAIL: first lock"; cat bats.lock; exit 1; }
publish "2026-01-02T00:00:20Z"
"$BATS" lock --repository "$TMP/repo" > /dev/null 2>&1
grep -q '^latestdep 2026.1.2.20 ' bats.lock || { echo "FAIL: relock kept the old version"; cat bats.lock; exit 1; }
echo "lock-latest: ok"
