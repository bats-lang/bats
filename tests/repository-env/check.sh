#!/bin/sh
# Without --repository, BATS_REPOSITORY names the package repository
# (bats-lang/bats#250), so a machine sets it once instead of passing
# the flag on every call; --repository, when given, wins.
# usage: tests/repository-env/check.sh <bats-binary> <repository-dir>
set -eu
BATS=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unset BATS_REPOSITORY
mkdir -p "$TMP/repo" "$TMP/dep/src" "$TMP/app/src"
printf '[package]\nname = "envdep"\nkind = "lib"\n' > "$TMP/dep/bats.toml"
printf '#pub fun f (): int\n\nimplement f () = 1\n' > "$TMP/dep/src/lib.bats"
printf 'build/\ndist/\ndocs/\n' > "$TMP/dep/.gitignore"
(cd "$TMP/dep" && git init -q -b main . && git add -A &&
 GIT_COMMITTER_DATE="2026-01-01T00:00:10Z" git -c user.name=t -c user.email=t@t commit -q -m t)
# upload with the variable alone
(cd "$TMP/dep" && BATS_REPOSITORY="$TMP/repo" "$BATS" upload) > "$TMP/up.log" 2>&1 || { echo "FAIL: upload with BATS_REPOSITORY"; cat "$TMP/up.log"; exit 1; }
ls "$TMP/repo/envdep/"*.bats > /dev/null 2>&1 || { echo "FAIL: upload did not write into BATS_REPOSITORY"; exit 1; }
printf '[package]\nname = "envapp"\nkind = "lib"\n\n[dependencies]\n"envdep" = ""\n' > "$TMP/app/bats.toml"
printf '#use envdep as D\n\n#pub fun g (): int\n\nimplement g () = 2\n' > "$TMP/app/src/lib.bats"
cd "$TMP/app"
BATS_REPOSITORY="$TMP/repo" "$BATS" lock > "$TMP/lock.log" 2>&1 || { echo "FAIL: lock with BATS_REPOSITORY"; cat "$TMP/lock.log"; exit 1; }
grep -q '^envdep 2026.1.1.10 ' bats.lock || { echo "FAIL: lock"; cat bats.lock; exit 1; }
rm -rf bats_modules
BATS_REPOSITORY="$TMP/repo" "$BATS" check > "$TMP/check.log" 2>&1 || { echo "FAIL: check with BATS_REPOSITORY"; cat "$TMP/check.log"; exit 1; }
# the flag wins over the variable
mkdir -p "$TMP/empty"
rm -rf bats_modules
if BATS_REPOSITORY="$TMP/repo" "$BATS" check --repository "$TMP/empty" > "$TMP/flag.log" 2>&1; then
  echo "FAIL: --repository did not win over BATS_REPOSITORY"; cat "$TMP/flag.log"; exit 1
fi
# neither: as before
rm -rf bats_modules
if "$BATS" check > "$TMP/none.log" 2>&1; then
  echo "FAIL: check without a repository fetched the locked package"; exit 1
fi
echo "repository-env: ok"
